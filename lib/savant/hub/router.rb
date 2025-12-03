# frozen_string_literal: true

require 'json'
require 'rack/request'

require_relative '../framework/middleware/user_header'
require_relative 'sse'
require_relative '../logging/event_recorder'
require_relative 'connections'
require_relative '../multiplexer'

module Savant
  module Hub
    # Lightweight hub router for multi-engine HTTP + SSE endpoints.
    # rubocop:disable Metrics/ClassLength
    class Router
      def self.build(mounts:, transport: 'http', heartbeat_interval: SSE::DEFAULT_HEARTBEAT_SECS, logs_dir: nil)
        new(mounts: mounts, transport: transport, heartbeat_interval: heartbeat_interval, logs_dir: logs_dir)
      end

      def initialize(mounts:, transport:, heartbeat_interval: SSE::DEFAULT_HEARTBEAT_SECS, logs_dir: nil)
        @mounts = mounts # { 'engine_name' => ServiceManager-like }
        @transport = transport
        @sse = SSE.new(heartbeat_interval: heartbeat_interval)
        @logs_dir = logs_dir || ENV['SAVANT_LOG_PATH'] || '/tmp/savant'
        @hub_logger = init_hub_logger
        @recorder = Savant::Logging::EventRecorder.global
        @connections = Savant::Hub::Connections.global
        @stats = { total: 0, by_engine: Hash.new(0), by_status: Hash.new(0), by_method: Hash.new(0), recent: [] }
        @stats_mutex = Mutex.new
      end

      def call(env)
        # Allow CORS preflight without requiring user header
        return [204, cors_headers, []] if env['REQUEST_METHOD'] == 'OPTIONS'

        Savant::Framework::Middleware::UserHeader.new(method(:dispatch)).call(env)
      end

      # Public: Return a simple overview of mounted engines for startup logs.
      def engine_overview
        mounts.map do |name, manager|
          { name: name,
            path: "/#{name}",
            mount: "/#{name}",
            tools: (safe_specs(manager) || []).size,
            status: 'running',
            uptime_seconds: (manager.respond_to?(:uptime) ? manager.uptime : 0) }
        end
      end

      # Public: Build a list of route entries similar to `rake routes`.
      # Each entry: { module:, method:, path:, description: }
      def routes(expand_tools: false)
        list = []
        list << { module: 'hub', method: 'GET', path: '/', description: 'Hub dashboard' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics', description: 'Env, mounts, repos visibility, DB checks' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/connections', description: 'Active SSE/stdio connections' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/agent', description: 'Agent runtime: memory + telemetry' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/agent/trace', description: 'Download agent trace log' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/agent/session', description: 'Download agent session memory JSON' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/workflows', description: 'Workflow engine telemetry (recent events)' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/workflow_runs', description: 'Saved workflow run metadata' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/workflow_runs/:workflow/:run_id', description: 'Workflow run details' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/workflows/trace', description: 'Download workflow trace JSONL' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/mcp/:name', description: 'Per-engine diagnostics' }
        list << { module: 'hub', method: 'GET', path: '/routes', description: 'Routes list (add ?expand=1 to include tool calls)' }
        list << { module: 'hub', method: 'GET', path: '/logs', description: 'Aggregated recent events (?n=100,&mcp=,&type=)' }
        list << { module: 'hub', method: 'GET', path: '/logs/stream', description: 'Aggregated live event stream (SSE)' }

        mounts.keys.sort.each do |engine_name|
          base = "/#{engine_name}"
          list << { module: engine_name, method: 'GET', path: "#{base}/status", description: 'Engine uptime and info' }
          list << { module: engine_name, method: 'GET', path: "#{base}/tools", description: 'List tool specs' }
          list << { module: engine_name, method: 'GET', path: "#{base}/logs", description: 'Tail last N lines as JSON (?n=100)' }
          list << { module: engine_name, method: 'GET', path: "#{base}/logs?stream=1", description: 'Stream logs via SSE (?n=100, &once=1)' }
          list << { module: engine_name, method: 'GET', path: "#{base}/stream", description: 'SSE heartbeat' }

          next unless expand_tools

          specs = safe_specs(mounts[engine_name])
          specs.each do |spec|
            name = spec[:name] || spec['name']
            desc = spec[:description] || spec['description'] || 'Tool call'
            list << { module: engine_name, method: 'POST', path: "#{base}/tools/#{name}/call", description: desc }
          end
        end
        list
      end

      private

      attr_reader :mounts, :transport, :sse, :logs_dir, :hub_logger

      def init_hub_logger
        require 'fileutils'
        FileUtils.mkdir_p(@logs_dir)
        path = File.join(@logs_dir, 'hub.log')
        io = File.open(path, 'a')
        io.sync = true
        require_relative '../logging/logger'
        Savant::Logging::Logger.new(io: io, json: true, service: 'hub')
      rescue StandardError
        nil
      end

      def log_request(req, status, duration_ms, response_body = nil)
        # Track stats
        engine = req.path_info.split('/').reject(&:empty?).first || 'hub'

        # Truncate response body for storage (keep first 4KB)
        truncated_body = nil
        if response_body
          body_str = response_body.is_a?(Array) ? response_body.join : response_body.to_s
          truncated_body = body_str.length > 4096 ? "#{body_str[0, 4096]}...[truncated]" : body_str
        end

        # Read request body if available (for POST requests)
        request_body = nil
        if req.request_method == 'POST'
          begin
            req.body.rewind if req.body.respond_to?(:rewind)
            raw = req.body.read
            req.body.rewind if req.body.respond_to?(:rewind)
            request_body = raw.length > 2048 ? "#{raw[0, 2048]}...[truncated]" : raw
          rescue StandardError
            # ignore
          end
        end

        @stats_mutex.synchronize do
          @stats[:total] += 1
          @stats[:by_engine][engine] += 1
          @stats[:by_status][status.to_s] += 1
          @stats[:by_method][req.request_method] += 1
          @stats[:recent].unshift({
                                    id: @stats[:total],
                                    time: Time.now.utc.iso8601,
                                    method: req.request_method,
                                    path: req.path_info,
                                    query: req.query_string.to_s.empty? ? nil : req.query_string,
                                    status: status,
                                    duration_ms: duration_ms,
                                    engine: engine,
                                    user: req.env['savant.user_id'],
                                    request_body: request_body,
                                    response_body: truncated_body
                                  })
          @stats[:recent] = @stats[:recent].first(100) # Keep last 100 requests
        end

        # EventRecorder (global) for unified streaming/logging
        begin
          @recorder.record(type: 'http_request', mcp: engine, method: req.request_method, path: req.path_info,
                           status: status, duration_ms: duration_ms, user: req.env['savant.user_id'],
                           query: (req.query_string.to_s.empty? ? nil : req.query_string),
                           request_body: request_body, response_body: truncated_body)
        rescue StandardError
          # ignore
        end

        return unless hub_logger

        hub_logger.info(
          event: 'http_request',
          method: req.request_method,
          path: req.path_info,
          status: status,
          duration_ms: duration_ms,
          user: req.env['savant.user_id'],
          query: req.query_string.to_s.empty? ? nil : req.query_string
        )
      rescue StandardError
        # ignore logging errors
      end

      def dispatch(env)
        req = Rack::Request.new(env)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        response = dispatch_request(req)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
        log_request(req, response[0], duration_ms, response[2])
        response
      rescue JSON::ParserError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
        response = respond(400, { error: 'invalid JSON', message: e.message })
        log_request(req, 400, duration_ms, response[2])
        response
      rescue StandardError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
        response = respond(500, { error: 'internal error', message: e.message })
        log_request(req, 500, duration_ms, response[2])
        response
      end

      def dispatch_request(req)
        return hub_root(req) if req.get? && req.path_info == '/'
        return hub_routes(req) if req.get? && req.path_info == '/routes'
        return diagnostics(req) if req.get? && req.path_info == '/diagnostics'
        return diagnostics_agent(req) if req.get? && %w[/diagnostics/agent /diagnostics/agents].include?(req.path_info)
        return diagnostics_agent_trace(req) if req.get? && req.path_info == '/diagnostics/agent/trace'
        return diagnostics_agent_session(req) if req.get? && req.path_info == '/diagnostics/agent/session'
        return diagnostics_connections(req) if req.get? && req.path_info == '/diagnostics/connections'
        return diagnostics_mcp(req) if req.get? && req.path_info.start_with?('/diagnostics/mcp/')
        return diagnostics_workflows(req) if req.get? && req.path_info == '/diagnostics/workflows'
        return diagnostics_workflow_runs(req) if req.get? && req.path_info == '/diagnostics/workflow_runs'
        if req.get?
          match = req.path_info.match(%r{^/diagnostics/workflow_runs/([^/]+)/([^/]+)$})
          return diagnostics_workflow_run(req, match[1], match[2]) if match
        end
        return diagnostics_workflows_trace(req) if req.get? && req.path_info == '/diagnostics/workflows/trace'
        return logs_index(req) if req.get? && req.path_info == '/logs'

        if req.get? && req.path_info.start_with?('/logs/')
          # Map /logs/:mcp to /logs?mcp=... but avoid /logs/stream
          parts = req.path_info.split('/').reject(&:empty?)
          if parts.length == 2 && parts[1] != 'stream'
            mcp = parts[1]
            req.update_param('mcp', mcp)
            return logs_index(req)
          end
        end
        return logs_stream(req) if req.get? && req.path_info == '/logs/stream'

        # Engine scoped routes: /:engine/...
        segments = req.path_info.split('/').reject(&:empty?)
        return not_found unless segments.size >= 1

        engine_name = segments[0]

        # Special handling for /hub/logs
        if engine_name == 'hub'
          return handle_hub_get(req, segments[1..]) if req.request_method == 'GET'

          return not_found
        end

        if engine_name == 'multiplexer'
          return handle_multiplexer_get(req, segments[1..]) if req.request_method == 'GET'

          return not_found
        end

        manager = mounts[engine_name]
        return not_found unless manager

        case req.request_method
        when 'GET'
          handle_get(req, engine_name, manager, segments[1..])
        when 'POST'
          handle_post(req, engine_name, manager, segments[1..])
        else
          not_found
        end
      end

      def handle_hub_get(req, rest)
        case rest
        when ['status']
          respond(200, {
                    engine: 'hub',
                    status: 'running',
                    uptime_seconds: uptime_seconds,
                    info: { name: 'hub', version: '3.0.0', description: 'Savant MCP Hub HTTP router and logging' }
                  })
        when ['stats']
          stats_snapshot = @stats_mutex.synchronize { deep_copy_stats(@stats) }
          respond(200, {
                    uptime_seconds: uptime_seconds,
                    requests: {
                      total: stats_snapshot[:total],
                      by_engine: stats_snapshot[:by_engine],
                      by_status: stats_snapshot[:by_status],
                      by_method: stats_snapshot[:by_method]
                    },
                    recent: stats_snapshot[:recent]
                  })
        when ['logs']
          if req.params['stream']
            sse_logs(req, 'hub')
          else
            n = (req.params['n'] || '100').to_i
            path = log_path('hub')
            return respond(200, { engine: 'hub', count: 0, path: path, lines: [], note: 'log file not found' }) unless File.file?(path)

            level = req.params['level']
            lines = filter_log_lines(read_last_lines(path, n), level)
            respond(200, { engine: 'hub', count: lines.length, path: path, lines: lines, level: level })
          end
        else
          not_found
        end
      end

      # GET /logs -> aggregated last N events across engines (via EventRecorder)
      def logs_index(req)
        n = (req.params['n'] || '100').to_i
        mcp = req.params['mcp']
        type = req.params['type']
        events = @recorder.last(n, mcp: (mcp unless mcp.to_s.empty?), type: (type unless type.to_s.empty?))
        respond(200, { count: events.length, events: events })
      end

      # GET /diagnostics/workflows -> recent workflow events
      def diagnostics_workflows(req)
        n = (req.params['n'] || '100').to_i
        events = @recorder.last(n, type: 'workflow_step')
        respond(200, { count: events.length, events: events })
      end

      # GET /diagnostics/workflow_runs -> saved runs summary
      def diagnostics_workflow_runs(_req) # GET /diagnostics/workflow_runs -> saved runs summary
        engine = workflow_engine
        respond(200, engine.runs_list)
      rescue StandardError => e
        respond(500, { error: 'workflow_runs_error', message: e.message })
      end

      def diagnostics_workflow_run(_req, workflow, run_id)
        base = workflow_base_path
        path = File.join(base, '.savant', 'workflow_runs', "#{workflow}__#{run_id}.json")
        return respond(404, { error: 'workflow_run_not_found', workflow: workflow, run_id: run_id }) unless File.file?(path)
        data = JSON.parse(File.read(path))
        respond(200, data)
      rescue StandardError => e
        respond(500, { error: 'workflow_run_error', message: e.message })
      end

      # GET /diagnostics/workflows/trace -> download JSONL trace file
      def diagnostics_workflows_trace(_req)
        base = if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
                 ENV['SAVANT_PATH']
               else
                 File.expand_path('../../..', __dir__)
               end
        path = File.join(base, 'logs', 'workflow_trace.log')
        return respond(404, { error: 'trace_not_found', path: path }) unless File.file?(path)
        data = File.read(path)
        [200, { 'Content-Type' => 'text/plain' }.merge(cors_headers), [data]]
      end

      def workflow_base_path
        if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
          ENV['SAVANT_PATH']
        else
          File.expand_path('../../..', __dir__)
        end
      end

      def workflow_engine
        require_relative '../engines/workflow/engine'
        Savant::Workflow::Engine.new(base_path: workflow_base_path)
      end

      # GET /logs/stream -> SSE unified stream of events
      def logs_stream(req)
        mcp = (req.params['mcp'] || '').to_s
        type = (req.params['type'] || '').to_s
        once = req.params.key?('once') && req.params['once'] != '0'
        user_id = req.env['savant.user_id']
        conn_id = @connections.connect(type: 'sse', mcp: (mcp.empty? ? nil : mcp), path: '/logs/stream', user_id: user_id)

        headers = sse_headers
        body = Enumerator.new do |y|
          # Send recent snapshot first
          @recorder.last(50, mcp: (mcp.empty? ? nil : mcp), type: (type.empty? ? nil : type)).each do |ev|
            y << format_sse_event('event', ev)
            @connections.touch(conn_id)
          end
          break if once

          src = @recorder.stream(mcp: (mcp.empty? ? nil : mcp), type: (type.empty? ? nil : type))
          src.each do |line|
            y << "event: event\ndata: #{line}\n\n"
            @connections.touch(conn_id)
          end
        ensure
          @connections.disconnect(conn_id)
        end
        [200, headers, body]
      end

      def handle_get(req, engine_name, manager, rest)
        case rest
        when ['tools']
          tools = safe_specs(manager)
          normalized = tools.map { |t| normalize_tool_spec(t) }
          respond(200, { engine: engine_name, tools: normalized })
        when *rest
          # Stream tool call via SSE: /:engine/tools/:name/stream
          if rest.length >= 3 && rest[0] == 'tools' && rest[-1] == 'stream'
            tool = rest[1..-2].join('/')
            sse_tool_call(req, engine_name, manager, tool)
          end
        when ['status']
          info = manager.service_info
          uptime = manager.respond_to?(:uptime) ? manager.uptime : 0
          respond(200, { engine: engine_name, status: 'running', uptime_seconds: uptime, info: info })
        when ['logs']
          if req.params['stream']
            sse_logs(req, engine_name)
          else
            n = (req.params['n'] || '100').to_i
            path = log_path(engine_name)
            unless File.file?(path)
              # Return empty set with note rather than 404 for better UX
              return respond(200, { engine: engine_name, count: 0, path: path, lines: [], note: 'log file not found' })
            end

            level = req.params['level']
            lines = filter_log_lines(read_last_lines(path, n), level)
            respond(200, { engine: engine_name, count: lines.length, path: path, lines: lines, level: level })
          end
        when ['stream']
          # Track SSE connection
          user_id = req.env['savant.user_id']
          conn_id = @connections.connect(type: 'sse', mcp: engine_name, path: "/#{engine_name}/stream", user_id: user_id)
          status, headers, body = sse.call(req.env)
          wrapped = Enumerator.new do |y|
            body.each do |chunk|
              y << chunk
              @connections.touch(conn_id)
            end
          ensure
            @connections.disconnect(conn_id)
          end
          [status, headers, wrapped]
        else
          not_found
        end
      end

      def handle_multiplexer_get(req, rest)
        case rest
        when ['logs']
          return sse_logs(req, 'multiplexer', log_file: multiplexer_log_path) if req.params['stream']

          n = (req.params['n'] || '100').to_i
          path = multiplexer_log_path
          return respond(200, { engine: 'multiplexer', count: 0, path: path, lines: [], note: 'log file not found' }) unless File.file?(path)

          level = req.params['level']
          lines = filter_log_lines(read_last_lines(path, n), level)
          respond(200, { engine: 'multiplexer', count: lines.length, path: path, lines: lines, level: level })
        else
          not_found
        end
      end

      def handle_post(req, engine_name, manager, rest)
        if rest.size >= 3 && rest[0] == 'tools' && rest[-1] == 'call'
          tool = rest[1..-2].join('/')
          payload = parse_json_body(req)
          params = payload.is_a?(Hash) ? (payload['params'] || {}) : {}
          result = call_with_user_context(manager, engine_name, tool, params, req.env['savant.user_id'])
          respond(200, result)
        else
          not_found
        end
      end

      def hub_root(_req)
        engines = engine_overview
        payload = {
          service: 'Savant MCP Hub',
          version: '3.0.0',
          transport: transport,
          hub: { pid: Process.pid, uptime_seconds: uptime_seconds },
          engines: engines
        }
        # Attach multiplexer snapshot if available; lazily start if not yet running
        mux = Savant::Multiplexer.global
        unless mux
          begin
            settings_path = File.join(base_path, 'config', 'settings.json')
            Savant::Multiplexer.ensure!(base_path: base_path, settings_path: settings_path)
            mux = Savant::Multiplexer.global
          rescue StandardError
            mux = nil
          end
        end
        payload[:multiplexer] = mux.snapshot if mux
        respond(200, payload)
      end

      def hub_routes(req)
        expand = %w[1 true].include?(req.params['expand'])
        respond(200, { routes: routes(expand_tools: expand) })
      end

      def base_path
        env_path = ENV['SAVANT_PATH']
        return env_path unless env_path.nil? || env_path.empty?

        File.expand_path('../../..', __dir__)
      end

      def diagnostics(_req)
        info = {}
        bp = base_path
        info[:base_path] = bp
        settings_path = File.join(bp, 'config', 'settings.json')
        info[:settings_path] = settings_path
        repos = []
        cfg_err = nil
        begin
          require_relative '../framework/config'
          if File.file?(settings_path)
            cfg = Savant::Framework::Config.load(settings_path)
            (cfg.dig('indexer', 'repos') || []).each do |r|
              name = r['name']
              path = r['path']
              repo_entry = { name: name, path: path }
              begin
                exists = File.exist?(path)
                repo_entry[:exists] = exists
                repo_entry[:directory] = exists && File.directory?(path)
                repo_entry[:readable] = exists && File.readable?(path)
                if repo_entry[:directory]
                  sample = []
                  count = 0
                  Dir.glob(File.join(path, '**', '*')).each do |p|
                    next if File.directory?(p)

                    sample << p if sample.size < 3
                    count += 1
                    break if count >= 200
                  end
                  repo_entry[:sample_files] = sample
                  repo_entry[:sampled_count] = count
                  repo_entry[:has_files] = count.positive?
                end
              rescue StandardError => e
                repo_entry[:error] = e.message
              end
              repos << repo_entry
            end
          else
            cfg_err = 'settings.json not found'
          end
        rescue Savant::ConfigError => e
          cfg_err = e.message
        rescue StandardError => e
          cfg_err = "load error: #{e.message}"
        end

        info[:config_error] = cfg_err if cfg_err
        info[:repos] = repos

        # DB checks
        db = { connected: false }
        begin
          require_relative '../framework/db'
          db_client = Savant::Framework::DB.new
          db_client.with_connection do |conn|
            conn.exec('SELECT 1')
            db[:connected] = true
            begin
              r1 = conn.exec('SELECT COUNT(*) AS c FROM repos')
              r2 = conn.exec('SELECT COUNT(*) AS c FROM files')
              r3 = conn.exec('SELECT COUNT(*) AS c FROM chunks')
              db[:counts] = { repos: r1[0]['c'].to_i, files: r2[0]['c'].to_i, chunks: r3[0]['c'].to_i }
            rescue StandardError => e
              db[:counts_error] = e.message
            end
          end
        rescue StandardError => e
          db[:error] = e.message
        end
        info[:db] = db

        # Common mount points
        info[:mounts] = {
          '/app' => File.directory?('/app'),
          '/host' => File.directory?('/host'),
          '/host-crawler' => File.directory?('/host-crawler')
        }

        # Secrets info: report resolved secrets file path (values are not exposed)
        begin
          secrets_path = if ENV['SAVANT_SECRETS_PATH'] && !ENV['SAVANT_SECRETS_PATH'].empty?
                           ENV['SAVANT_SECRETS_PATH']
                         else
                           root_candidate = File.join(bp, 'secrets.yml')
                           cfg_candidate = File.join(bp, 'config', 'secrets.yml')
                           File.file?(root_candidate) ? root_candidate : cfg_candidate
                         end
          info[:secrets] = {
            path: secrets_path,
            exists: File.file?(secrets_path)
          }
        rescue StandardError
          # ignore
        end

        respond(200, info)
      end

      def uptime_seconds
        @started ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started).to_i
      end

      def parse_json_body(req)
        req.body.rewind if req.body.respond_to?(:rewind)
        raw = req.body.read.to_s
        req.body.rewind if req.body.respond_to?(:rewind)
        return {} if raw.empty?

        JSON.parse(raw)
      end

      def respond(status, body_hash)
        [status, { 'Content-Type' => 'application/json' }.merge(cors_headers), [JSON.generate(body_hash)]]
      end

      def not_found
        respond(404, { error: 'not found' })
      end

      def log_path(engine_name)
        File.join(logs_dir, "#{engine_name}.log")
      end

      def multiplexer_log_path
        mux = Savant::Multiplexer.global
        path = mux&.snapshot&.[](:log_path)
        return path if path && !path.to_s.empty?

        log_path('multiplexer')
      rescue StandardError
        log_path('multiplexer')
      end

      def cors_headers
        allow_origin = ENV['SAVANT_CORS_ORIGIN'] || '*'
        {
          'Access-Control-Allow-Origin' => allow_origin,
          'Access-Control-Allow-Headers' => 'content-type, x-savant-user-id',
          'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS'
        }
      end

      def read_last_lines(path, line_count)
        return [] unless File.file?(path)

        lines = []
        File.foreach(path) { |line| lines << line.chomp }
        lines.last(line_count)
      end

      def deep_copy_stats(stats)
        {
          total: stats[:total],
          by_engine: stats[:by_engine].dup,
          by_status: stats[:by_status].dup,
          by_method: stats[:by_method].dup,
          recent: stats[:recent].map(&:dup)
        }
      end

      def safe_specs(manager)
        # Avoid instantiating engines on startup summary; require tools file and build registrar with nil engine
        svc = (manager.respond_to?(:service) ? manager.service.to_s : nil)
        return [] if svc.nil? || svc.empty?

        begin
          require File.join(__dir__, '..', 'engines', svc, 'tools')
          camel = svc.split(/[^a-zA-Z0-9]/).map { |seg| seg.empty? ? '' : seg[0].upcase + seg[1..] }.join
          mod = Savant.const_get(camel)
          tools_mod = mod.const_get(:Tools)
          reg = tools_mod.build_registrar(nil)
          reg.specs
        rescue StandardError
          []
        end
      end

      def call_with_user_context(manager, engine_name, tool, params, user_id)
        tool_candidates = [tool]
        # Generate common alias variants to improve robustness across engines
        begin
          t = tool.to_s
          tool_candidates << t.tr('/', '_') if t.include?('/')
          tool_candidates << t.tr('_', '/') if t.include?('_')
          tool_candidates << t.tr('.', '/') if t.include?('.')
          tool_candidates << t.tr('.', '_') if t.include?('.')
          # Context engine historically uses snake_case; prefer underscore variant
          if engine_name.to_s == 'context'
            tool_candidates << t.tr('/', '_')
          end
        rescue StandardError
          # ignore
        end
        tool_candidates = tool_candidates.uniq

        # Prefer registrar to pass user_id in ctx (enables per-user creds middleware)
        # Also log per-engine tool calls so /:engine/logs has content.
        logger = nil
        begin
          path = log_path(engine_name)
          require_relative '../logging/logger'
          logger = Savant::Logging::Logger.new(io: $stdout, file_path: path, json: true, service: engine_name)
        rescue StandardError
          logger = nil
        end

        tool_candidates.each do |name_variant|
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          logger&.info(event: 'tool.call start', name: name_variant, user: user_id)
          # Try registrar via specs (ensures load)
          begin
            manager.specs
            reg = manager.send(:registrar)
            result = reg.call(name_variant, params, ctx: { engine: engine_name, user_id: user_id })
            dur = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
            logger&.info(event: 'tool.call finish', name: name_variant, duration_ms: dur)
            return result
          rescue StandardError
            # try next strategy
          end

          # Try public registrar accessor
          if manager.respond_to?(:registrar)
            begin
              result = manager.registrar.call(name_variant, params, ctx: { engine: engine_name, user_id: user_id })
              dur = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
              logger&.info(event: 'tool.call finish', name: name_variant, duration_ms: dur)
              return result
            rescue StandardError
              # Hot reload fallback
              begin
                result = hot_reload_and_call(engine_name, name_variant, params, user_id)
                dur = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
                logger&.info(event: 'tool.call finish', name: name_variant, duration_ms: dur)
                return result
              rescue StandardError
                # try next candidate
              end
            end
          end

          # Last resort: use manager.call_tool
          begin
            result = manager.call_tool(name_variant, params)
            dur = ((Process.clock_gettime(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round rescue 0)
            logger&.info(event: 'tool.call finish', name: name_variant, duration_ms: dur)
            return result
          rescue StandardError
            begin
              result = hot_reload_and_call(engine_name, name_variant, params, user_id)
              dur = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
              logger&.info(event: 'tool.call finish', name: name_variant, duration_ms: dur)
              return result
            rescue StandardError
              # continue loop
            end
          end
        end
        # All variants failed; re-raise using original name
        raise StandardError, 'Unknown tool'
      end

      # Load fresh engine + tools for the given engine and dispatch the tool call.
      def hot_reload_and_call(engine_name, tool, params, user_id)
        camel = engine_name.split(/[^a-zA-Z0-9]/).map { |seg| seg.empty? ? '' : seg[0].upcase + seg[1..] }.join
        require File.join(__dir__, '..', 'engines', engine_name, 'engine')
        require File.join(__dir__, '..', 'engines', engine_name, 'tools')
        mod = Savant.const_get(camel)
        engine = mod.const_get(:Engine).new
        tools_mod = mod.const_get(:Tools)
        reg = tools_mod.build_registrar(engine)
        reg.call(tool, params, ctx: { engine: engine_name, user_id: user_id })
      end

      def sse_headers
        {
          'Content-Type' => 'text/event-stream',
          'Cache-Control' => 'no-cache',
          'X-Accel-Buffering' => 'no'
        }.merge(cors_headers)
      end

      def format_sse_event(event, data)
        "event: #{event}\n" \
          "data: #{JSON.generate(data)}\n\n"
      end

      def sse_logs(req, engine_name, log_file: nil)
        n = (req.params['n'] || '100').to_i
        once = req.params.key?('once') && req.params['once'] != '0'
        level = req.params['level']
        level_pattern = log_level_pattern(level)
        path = log_file || log_path(engine_name)
        unless File.file?(path)
          body = Enumerator.new do |y|
            y << format_sse_event('log', { line: 'log file not found' })
            y << format_sse_event('done', {})
          end
          return [200, sse_headers, body]
        end

        user_id = req.env['savant.user_id']
        conn_id = @connections.connect(type: 'sse', mcp: engine_name, path: "/#{engine_name}/logs", user_id: user_id)
        body = Enumerator.new do |y|
          # Emit last N lines immediately
          read_last_lines(path, n).each do |line|
            next if level_pattern && !level_pattern.match?(line)

            safe = begin
              s = line.to_s.dup
              s.force_encoding('UTF-8')
              s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
            rescue StandardError
              line.to_s
            end
            y << format_sse_event('log', { line: safe })
            @connections.touch(conn_id)
          end
          break if once

          # Follow mode: stream appended lines
          File.open(path, 'r') do |f|
            pos = f.size
            loop do
              size = File.size(path)
              if size > pos
                f.seek(pos)
                chunk = f.read(size - pos)
                pos = size
                chunk.to_s.split(/\r?\n/).each do |ln|
                  next if ln.empty? || (level_pattern && !level_pattern.match?(ln))

                  safe = begin
                    s = ln.to_s.dup
                    s.force_encoding('UTF-8')
                    s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
                  rescue StandardError
                    ln.to_s
                  end
                  y << format_sse_event('log', { line: safe })
                  @connections.touch(conn_id)
                end
              end
              sleep 0.5
            end
          end
        rescue StandardError
          # Client disconnect or file issues; end stream
        ensure
          @connections.disconnect(conn_id)
        end

        [200, sse_headers, body]
      end

      # GET /diagnostics/connections -> list current connections
      def diagnostics_connections(_req)
        list = @connections.list
        respond(200, { connections: list, count: list.length })
      end

      # GET /diagnostics/mcp/:name -> per-engine diagnostics
      def diagnostics_mcp(req)
        name = req.path_info.split('/').last
        manager = mounts[name]
        return not_found unless manager

        info = begin
          manager.service_info
        rescue StandardError
          { name: name, version: 'unknown' }
        end
        engine_stats = @stats_mutex.synchronize do
          {
            requests: @stats[:by_engine][name] || 0,
            recent_requests: @stats[:recent].select { |r| r[:engine] == name }.first(20)
          }
        end
        conns = @connections.list(mcp: name)
        calls = { total_tool_calls: (manager.respond_to?(:total_tool_calls) ? manager.total_tool_calls : nil), last_seen: (manager.respond_to?(:last_seen) ? manager.last_seen : nil) }
        events = @recorder.last(50, mcp: name)
        respond(200, { engine: name, info: info, connections: conns, calls: calls, stats: engine_stats, recent_events: events })
      end

      # GET /diagnostics/agent(s) -> memory snapshot + recent reasoning events
      def diagnostics_agent(_req)
        base = base_path
        # Memory snapshot
        mem_path = File.join(base, '.savant', 'session.json')
        mem = if File.file?(mem_path)
                begin
                  JSON.parse(File.read(mem_path))
                rescue StandardError
                  nil
                end
              end

        # Telemetry: prefer recorder, but also merge from file so CLI sessions appear
        file_steps = []
        trace_path = File.join(base, 'logs', 'agent_trace.log')
        if File.file?(trace_path)
          begin
            lines = read_last_lines(trace_path, 1000)
            file_events = lines.map do |ln|
              JSON.parse(ln)
            rescue StandardError
              nil
            end.compact
            file_steps = file_events.select { |e| (e['type'] || e[:type]) == 'reasoning_step' }
          rescue StandardError
            file_steps = []
          end
        end

        rec_steps = @recorder.last(200, type: 'reasoning_step')
        # Merge and de-dup by step+timestamp hash if available
        merged = (rec_steps + file_steps).uniq do |e|
          k = if e.is_a?(Hash)
                e
              else
                (e.respond_to?(:to_h) ? e.to_h : {})
              end
          "#{k['timestamp'] || k[:timestamp]}:#{k['step'] || k[:step]}"
        end

        # Fallback: synthesize reasoning events from memory steps if no telemetry was captured
        if (merged.nil? || merged.empty?) && mem && mem['steps'].is_a?(Array) && mem['steps'].any?
          begin
            merged = mem['steps'].map do |s|
              a = s['action'] || {}
              {
                'type' => 'reasoning_step',
                'step' => s['index'] || s['idx'] || 0,
                'model' => nil,
                'prompt_tokens' => nil,
                'output_tokens' => nil,
                'action' => a['action'] || a[:action] || 'unknown',
                'tool_name' => a['tool_name'] || a[:tool_name] || '',
                'metadata' => { 'decision_summary' => a['reasoning'] || a[:reasoning] || '' },
                'timestamp' => Time.now.to_i
              }
            end
          rescue StandardError
            # ignore synthesis errors
          end
        end

        respond(200, { memory_path: mem_path, memory: mem, events_count: merged.length, events: merged, trace_path: trace_path })
      end

      # GET /diagnostics/agent/trace -> return agent trace log (plain text)
      def diagnostics_agent_trace(_req)
        path = File.join(base_path, 'logs', 'agent_trace.log')
        return respond(404, { error: 'trace_not_found', path: path }) unless File.file?(path)

        body = read_last_lines(path, 5000).join("\n")
        [200, { 'Content-Type' => 'text/plain' }.merge(cors_headers), [body]]
      end

      # GET /diagnostics/agent/session -> return session.json (application/json)
      def diagnostics_agent_session(_req)
        path = File.join(base_path, '.savant', 'session.json')
        return respond(404, { error: 'session_not_found', path: path }) unless File.file?(path)

        begin
          js = JSON.parse(File.read(path))
        rescue StandardError => e
          return respond(500, { error: 'session_parse_error', message: e.message })
        end
        [200, { 'Content-Type' => 'application/json' }.merge(cors_headers), [JSON.generate(js)]]
      end

      def normalize_tool_spec(spec)
        return spec unless spec.is_a?(Hash)

        h = {}
        spec.each { |k, v| h[k.to_s] = v }
        schema = h['inputSchema'] || h['schema'] || h['input_schema'] || {}
        h['inputSchema'] = schema
        h['schema'] = schema
        h['name'] = h['name'] || spec[:name]
        h['description'] = h['description'] || spec[:description]
        h
      end

      def filter_log_lines(lines, level)
        pattern = log_level_pattern(level)
        return lines unless pattern

        lines.select { |line| pattern.match?(line) }
      end

      def log_level_pattern(level)
        return nil if level.nil?

        normalized = level.to_s.downcase.strip
        return nil if normalized.empty? || normalized == 'all'

        case normalized
        when 'debug'
          /debug/i
        when 'info'
          /info/i
        when 'warn', 'warning'
          /warn/i
        when 'error', 'err', 'fatal'
          /(error|fatal|exception)/i
        end
      end

      def sse_tool_call(req, engine_name, manager, tool)
        # Params passed as JSON string via ?params=... to fit GET semantics
        raw = (req.params['params'] || '').to_s
        params = {}
        begin
          params = raw.empty? ? {} : JSON.parse(raw)
        rescue StandardError
          params = {}
        end
        user_id = req.env['savant.user_id']

        conn_id = @connections.connect(type: 'sse', mcp: engine_name, path: "/#{engine_name}/tools/#{tool}/stream", user_id: user_id)
        body = Enumerator.new do |y|
          y << format_sse_event('start', { tool: tool })
          begin
            result = call_with_user_context(manager, engine_name, tool, params, user_id)
            y << format_sse_event('result', result)
            y << format_sse_event('done', {})
          rescue StandardError => e
            y << format_sse_event('error', { message: e.message })
          end
        ensure
          @connections.disconnect(conn_id)
        end
        [200, sse_headers, body]
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
