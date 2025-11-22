# frozen_string_literal: true

require 'json'
require 'rack/request'

require_relative '../middleware/user_header'
require_relative 'sse'

module Savant
  module HTTP
    # Lightweight hub router for multi-engine HTTP + SSE endpoints.
    class Router
      def self.build(mounts:, transport: 'http', heartbeat_interval: SSE::DEFAULT_HEARTBEAT_SECS, logs_dir: nil)
        new(mounts: mounts, transport: transport, heartbeat_interval: heartbeat_interval, logs_dir: logs_dir)
      end

      def initialize(mounts:, transport:, heartbeat_interval: SSE::DEFAULT_HEARTBEAT_SECS, logs_dir: nil)
        @mounts = mounts # { 'engine_name' => ServiceManager-like }
        @transport = transport
        @sse = SSE.new(heartbeat_interval: heartbeat_interval)
        @logs_dir = logs_dir || ENV['SAVANT_LOG_PATH'] || '/tmp/savant'
      end

      def call(env)
        # Allow CORS preflight without requiring user header
        if env['REQUEST_METHOD'] == 'OPTIONS'
          return [204, cors_headers, []]
        end
        Savant::Middleware::UserHeader.new(method(:dispatch)).call(env)
      end

      # Public: Return a simple overview of mounted engines for startup logs.
      def engine_overview
        mounts.map do |name, manager|
          { name: name,
            path: "/#{name}",
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
        list << { module: 'hub', method: 'GET', path: '/routes', description: 'Routes list (add ?expand=1 to include tool calls)' }

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

      attr_reader :mounts, :transport, :sse, :logs_dir

      def dispatch(env)
        req = Rack::Request.new(env)
        return hub_root(req) if req.get? && req.path_info == '/'
        return hub_routes(req) if req.get? && req.path_info == '/routes'
        return diagnostics(req) if req.get? && req.path_info == '/diagnostics'

        # Engine scoped routes: /:engine/...
        segments = req.path_info.split('/').reject(&:empty?)
        return not_found unless segments.size >= 1

        engine_name = segments[0]
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
      rescue JSON::ParserError
        respond(400, { error: 'invalid JSON' })
      rescue StandardError => e
        respond(500, { error: 'internal error', message: e.message })
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
            return sse_tool_call(req, engine_name, manager, tool)
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
            lines = read_last_lines(path, n)
            respond(200, { engine: engine_name, count: lines.length, path: path, lines: lines })
          end
        when ['stream']
          sse.call(req.env)
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
        respond(200, payload)
      end

      def hub_routes(req)
        expand = req.params['expand'] == '1' || req.params['expand'] == 'true'
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
          require_relative '../config'
          if File.file?(settings_path)
            cfg = Savant::Config.load(settings_path)
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
                  repo_entry[:has_files] = count > 0
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
          require_relative '../db'
          conn = Savant::DB.new.instance_variable_get(:@conn)
          db[:connected] = true
          begin
            r1 = conn.exec('SELECT COUNT(*) AS c FROM repos')
            r2 = conn.exec('SELECT COUNT(*) AS c FROM files')
            r3 = conn.exec('SELECT COUNT(*) AS c FROM chunks')
            db[:counts] = { repos: r1[0]['c'].to_i, files: r2[0]['c'].to_i, chunks: r3[0]['c'].to_i }
          rescue StandardError => e
            db[:counts_error] = e.message
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

      def cors_headers
        allow_origin = ENV['SAVANT_CORS_ORIGIN'] || '*'
        {
          'Access-Control-Allow-Origin' => allow_origin,
          'Access-Control-Allow-Headers' => 'content-type, x-savant-user-id',
          'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS'
        }
      end

      def read_last_lines(path, n)
        return [] unless File.file?(path)
        lines = []
        File.foreach(path) { |l| lines << l.chomp }
        lines.last(n)
      end

      def safe_specs(manager)
        # Avoid instantiating engines on startup summary; require tools file and build registrar with nil engine
        svc = (manager.respond_to?(:service) ? manager.service.to_s : nil)
        return [] if svc.nil? || svc.empty?

        begin
          require File.join(__dir__, '..', svc, 'tools')
          camel = svc.split(/[^a-zA-Z0-9]/).map { |seg| seg.empty? ? '' : seg[0].upcase + seg[1..] }.join
          mod = Savant.const_get(camel)
          tools_mod = mod.const_get(:Tools)
          reg = tools_mod.build_registrar(nil)
          return reg.specs
        rescue StandardError
          return []
        end
      end

      def call_with_user_context(manager, engine_name, tool, params, user_id)
        # Prefer registrar to pass user_id in ctx (enables per-user creds middleware)
        begin
          manager.specs # ensure service is loaded when ServiceManager
          reg = manager.send(:registrar)
          return reg.call(tool, params, ctx: { engine: engine_name, user_id: user_id })
        rescue StandardError
          # Fall through to other strategies
        end

        if manager.respond_to?(:registrar)
          return manager.registrar.call(tool, params, ctx: { engine: engine_name, user_id: user_id })
        end

        # Last resort: use public API (no user context)
        manager.call_tool(tool, params)
      end

      def sse_headers
        {
          'Content-Type' => 'text/event-stream',
          'Cache-Control' => 'no-cache',
          'X-Accel-Buffering' => 'no'
        }.merge(cors_headers)
      end

      def format_sse_event(event, data)
        "event: #{event}\n" +
          "data: #{JSON.generate(data)}\n\n"
      end

      def sse_logs(req, engine_name)
        n = (req.params['n'] || '100').to_i
        once = req.params.key?('once') && req.params['once'] != '0'
        path = log_path(engine_name)
        unless File.file?(path)
          body = Enumerator.new do |y|
            y << format_sse_event('log', { line: 'log file not found' })
            y << format_sse_event('done', {})
          end
          return [200, sse_headers, body]
        end

        body = Enumerator.new do |y|
          # Emit last N lines immediately
          read_last_lines(path, n).each do |line|
            y << format_sse_event('log', { line: line })
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
                  next if ln.empty?
                  y << format_sse_event('log', { line: ln })
                end
              end
              sleep 0.5
            end
          end
        rescue StandardError
          # Client disconnect or file issues; end stream
        end

        [200, sse_headers, body]
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

        body = Enumerator.new do |y|
          y << format_sse_event('start', { tool: tool })
          begin
            result = call_with_user_context(manager, engine_name, tool, params, user_id)
            y << format_sse_event('result', result)
            y << format_sse_event('done', {})
          rescue StandardError => e
            y << format_sse_event('error', { message: e.message })
          end
        end
        [200, sse_headers, body]
      end

    end
  end
end
