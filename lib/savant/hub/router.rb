# frozen_string_literal: true

require 'json'
require 'rack/request'

require_relative '../framework/middleware/user_header'
require_relative 'sse'
require_relative '../logging/event_recorder'
require_relative 'connections'
require_relative '../multiplexer'
require_relative '../version'

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
        # Prefer explicit logs_dir, then env SAVANT_LOG_PATH, otherwise default to repo logs/
        env_logs = ENV['SAVANT_LOG_PATH']
        @logs_dir = logs_dir || (env_logs && !env_logs.empty? ? env_logs : File.join(base_path, 'logs'))
        @hub_logger = nil
        @hub_mongo_logger = init_hub_mongo_logger
        @recorder = Savant::Logging::EventRecorder.global
        @connections = Savant::Hub::Connections.global
        @stats = { total: 0, by_engine: Hash.new(0), by_status: Hash.new(0), by_method: Hash.new(0), recent: [] }
        @stats_mutex = Mutex.new
        @engine_loggers = {}
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
        list << { module: 'hub', method: 'GET', path: '/diagnostics/reasoning', description: 'Reasoning API diagnostics (reachability, usage)' }
        list << { module: 'hub', method: 'DELETE', path: '/diagnostics/reasoning', description: 'Clear Reasoning activity (Mongo + in-memory)' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/jira', description: 'Jira credentials presence (no secrets leaked)' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/connections', description: 'Active SSE/stdio connections' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/agent', description: 'Agent runtime: memory + telemetry' }
        list << { module: 'hub', method: 'DELETE', path: '/diagnostics/agent', description: 'Clear agent logs and session data' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/agent/trace', description: 'Download agent trace log' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/agent/session', description: 'Download agent session memory JSON' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/workflows', description: 'Workflow engine telemetry (recent events)' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/workflow_runs', description: 'Saved workflow run metadata' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/workflow_runs/:workflow/:run_id', description: 'Workflow run details' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/workflows/trace', description: 'Download workflow trace JSONL' }
        list << { module: 'hub', method: 'GET', path: '/diagnostics/mcp/:name', description: 'Per-engine diagnostics' }
        list << { module: 'hub', method: 'GET', path: '/routes', description: 'Routes list (add ?expand=1 to include tool calls)' }
        list << { module: 'hub', method: 'GET', path: '/logs', description: 'Aggregated recent events from Mongo (?n=100,&mcp=,&since=ISO8601)' }

        mounts.keys.sort.each do |engine_name|
          base = "/#{engine_name}"
          list << { module: engine_name, method: 'GET', path: "#{base}/status", description: 'Engine uptime and info' }
          list << { module: engine_name, method: 'GET', path: "#{base}/tools", description: 'List tool specs' }
          list << { module: engine_name, method: 'GET', path: "#{base}/logs", description: 'Recent logs from Mongo (?n=100,&since=ISO8601)' }
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

      def init_hub_mongo_logger
        begin
          require_relative '../logging/mongo_logger'
          Savant::Logging::MongoLogger.new(service: 'hub', collection: 'hub')
        rescue StandardError
          nil
        end
      end

      # --- Mongo helpers for polling logs ---
      def mongo_available?
        return @mongo_available if defined?(@mongo_available)
        begin
          require 'mongo'
          @mongo_available = true
        rescue LoadError
          @mongo_available = false
        end
        @mongo_available
      end

      def mongo_client
        return nil unless mongo_available?
        now = Time.now
        return nil if @mongo_disabled_until && now < @mongo_disabled_until
        if defined?(@mongo_client) && @mongo_client
          return @mongo_client
        end
        begin
          uri = ENV.fetch('MONGO_URI', "mongodb://#{mongo_host}/#{mongo_db_name}")
          client = Mongo::Client.new(uri, server_selection_timeout: 1.5, connect_timeout: 1.5, socket_timeout: 2)
          # Lightweight ping to ensure connectivity
          client.database.collections # probes server
          @mongo_client = client
        rescue StandardError
          # Back off further attempts for a short window to avoid blocking requests repeatedly
          @mongo_disabled_until = now + 10
          @mongo_client = nil
        end
        @mongo_client
      end

      def mongo_host
        ENV.fetch('MONGO_HOST', 'localhost:27017')
      end

      def mongo_db_name
        env = ENV.fetch('SAVANT_ENV', ENV.fetch('RACK_ENV', ENV.fetch('RAILS_ENV', 'development')))
        env == 'test' ? 'savant_test' : 'savant_development'
      end

      def mongo_collections
        return [] unless (cli = mongo_client)
        # Cache collection names briefly to reduce load
        now = Time.now
        if @mongo_col_cache && @mongo_col_cache[:ts] && (now - @mongo_col_cache[:ts] < 5)
          return @mongo_col_cache[:names]
        end
        begin
          names = cli.database.collections.map(&:name)
          @mongo_col_cache = { names: names, ts: now }
          names
        rescue StandardError
          []
        end
      end

      def mongo_fetch_aggregated(n:, mcp: nil, since: nil)
        return [] unless mongo_client
        t_since = parse_time_iso8601(since)
        names = mongo_collections.select { |nm| nm == 'hub' || nm.end_with?('_logs') }
        docs = []
        names.each do |nm|
          col = mongo_client[nm]
          filter = {}
          filter['service'] = { '$regex' => "^#{Regexp.escape(mcp)}" } if mcp
          filter['timestamp'] = { '$gt' => t_since } if t_since
          begin
            col.find(filter).sort({ timestamp: -1 }).limit([n, 500].min).each do |d|
              docs << normalize_mongo_doc(d)
            end
          rescue StandardError
            # ignore collection-level errors
          end
        end
        # Sort across collections and cap to n
        docs.sort_by { |d| d['timestamp'].to_s }.reverse.first(n)
      end

      def mongo_fetch_service(service_prefix:, n:, since: nil)
        return [] unless mongo_client
        t_since = parse_time_iso8601(since)
        names = mongo_collections.select { |nm| nm == 'hub' || nm.end_with?('_logs') }
        docs = []
        names.each do |nm|
          col = mongo_client[nm]
          filter = { 'service' => { '$regex' => "^#{Regexp.escape(service_prefix)}(\\.|$)" } }
          filter['timestamp'] = { '$gt' => t_since } if t_since
          begin
            col.find(filter).sort({ timestamp: -1 }).limit([n, 500].min).each do |d|
              docs << normalize_mongo_doc(d)
            end
          rescue StandardError
            # ignore
          end
        end
        docs.sort_by { |d| d['timestamp'].to_s }.reverse.first(n)
      end

      def parse_time_iso8601(str)
        return nil if str.nil? || str.to_s.strip.empty?
        Time.iso8601(str)
      rescue ArgumentError
        nil
      end

      def normalize_mongo_doc(doc)
        h = doc.dup
        # Normalize keys to strings and convert BSON::ObjectId
        h = h.transform_keys(&:to_s)
        h['_id'] = h['_id'].to_s if h['_id'] && h['_id'].respond_to?(:to_s)
        # Ensure timestamp is ISO 8601
        if h['timestamp'].respond_to?(:iso8601)
          h['timestamp'] = h['timestamp'].iso8601(3)
        else
          h['timestamp'] = Time.parse(h['timestamp'].to_s).iso8601(3) rescue h['timestamp'].to_s
        end
        h
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

        if @hub_mongo_logger
          payload = {
            event: 'http_request',
            method: req.request_method,
            path: req.path_info,
            status: status,
            duration_ms: duration_ms,
            user: req.env['savant.user_id'],
            query: req.query_string.to_s.empty? ? nil : req.query_string
          }
          # Include small request/response bodies for API introspection (already truncated above)
          payload[:request_body] = request_body if request_body && !request_body.empty?
          payload[:response_body] = truncated_body if truncated_body && !truncated_body.empty?
          @hub_mongo_logger.info(payload)
        end
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
        return diagnostics_reasoning(req) if req.get? && req.path_info == '/diagnostics/reasoning'
        return diagnostics_reasoning_clear(req) if req.delete? && req.path_info == '/diagnostics/reasoning'
        return diagnostics_jira(req) if req.get? && req.path_info == '/diagnostics/jira'
        # Reasoning callbacks (webhook)
        return callbacks_reasoning_agent_intent(req) if req.post? && req.path_info == '/callbacks/reasoning/agent_intent'
        return diagnostics_agent(req) if req.get? && %w[/diagnostics/agent /diagnostics/agents].include?(req.path_info)
        return diagnostics_agent_clear(req) if req.delete? && %w[/diagnostics/agent /diagnostics/agents].include?(req.path_info)
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
        # Streaming disabled for logs; use polling via GET /logs

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

      # POST /callbacks/reasoning/agent_intent -> receive async intent from Reasoning API
      def callbacks_reasoning_agent_intent(req)
        js = parse_json_body(req)
        # Record to in-memory events for UI visibility
        begin
          @recorder.record(type: 'agent_intent', mcp: 'reasoning', correlation_id: js['correlation_id'], job_id: js['job_id'], tool: js['tool_name'], finish: js['finish'], status: js['status'], ts: Time.now.utc.iso8601, timestamp: Time.now.to_i)
        rescue StandardError
          # ignore recorder problems
        end
        # Write to Mongo logs for aggregation
        begin
          Savant::Logging::MongoLogger.new(service: 'reasoning_hooks').info(event: 'agent_intent_delivered', correlation_id: js['correlation_id'], job_id: js['job_id'], tool: js['tool_name'], finish: js['finish'], status: js['status'])
        rescue StandardError
          # ignore logging problems
        end
        respond(200, { ok: true })
      end

      # GET /diagnostics/jira -> presence/shape of Jira credentials for current user
      # This endpoint never returns secret values; only booleans and source info.
      def diagnostics_jira(req)
        user_id = req.env['savant.user_id']
        out = { user: user_id, resolved_user: nil, source: 'none', fields: {}, auth_mode: 'missing', allow_writes: nil, problems: [], suggestions: [] }
        begin
          require_relative '../framework/secret_store'
        rescue StandardError
          # ignore
        end

        creds = nil
        resolved_user = nil
        source = 'none'
        begin
          # Prefer exact user, then default, then _system_
          if defined?(Savant::Framework::SecretStore)
            [user_id, 'default', '_system_'].compact.each do |uid|
              h = Savant::Framework::SecretStore.for(uid, :jira)
              next unless h && !h.empty?

              creds = h
              resolved_user = uid
              source = 'secret_store'
              break
            end
          end
        rescue StandardError
          # ignore
        end

        # ENV fallback only if SecretStore missing
        if creds.nil?
          env = ENV
          creds = {
            base_url: env['JIRA_BASE_URL'],
            email: env['JIRA_EMAIL'],
            api_token: env['JIRA_API_TOKEN'],
            username: env['JIRA_USERNAME'],
            password: env['JIRA_PASSWORD'],
            allow_writes: env['JIRA_ALLOW_WRITES']
          }
          source = 'env'
          resolved_user ||= user_id
        end

        def present?(v)
          !(v.nil? || v.to_s.strip.empty?)
        end

        base_url = creds[:base_url] || creds['base_url'] || creds[:jira_base_url] || creds['jira_base_url']
        email = creds[:email] || creds['email'] || creds[:jira_email] || creds['jira_email']
        api_token = creds[:api_token] || creds['api_token'] || creds[:jira_token] || creds['jira_token']
        username = creds[:username] || creds['username']
        password = creds[:password] || creds['password']
        allow_writes_raw = creds[:allow_writes] || creds['allow_writes']
        allow_writes = %w[true 1 yes].include?(allow_writes_raw.to_s.downcase)

        fields = {
          base_url: present?(base_url),
          email: present?(email),
          api_token: present?(api_token),
          username: present?(username),
          password: present?(password)
        }

        auth_mode = if fields[:email] && fields[:api_token]
                      'email+token'
                    elsif fields[:username] && fields[:password]
                      'username+password'
                    else
                      'missing'
                    end

        problems = []
        suggestions = []
        problems << 'missing base_url' unless fields[:base_url]
        problems << 'missing auth (email+token or username+password)' if auth_mode == 'missing'
        suggestions << 'Set secrets.yml users:<user>.jira.{base_url,email,api_token}' if source == 'env' || auth_mode == 'missing'
        suggestions << 'Ensure UI Settings user matches secrets.yml user (e.g., default)' if resolved_user != user_id

        out[:resolved_user] = resolved_user
        out[:source] = source
        out[:fields] = fields
        out[:auth_mode] = auth_mode
        out[:allow_writes] = allow_writes
        out[:problems] = problems
        out[:suggestions] = suggestions
        respond(200, out)
      end

      def handle_hub_get(req, rest)
        case rest
        when ['status']
          respond(200, {
                    engine: 'hub',
                    status: 'running',
                    uptime_seconds: uptime_seconds,
                    info: { name: 'hub', version: Savant::VERSION, description: 'Savant MCP Hub HTTP router and logging' }
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
          n = (req.params['n'] || '100').to_i
          since = (req.params['since'] || '').to_s
          logs = mongo_fetch_service(service_prefix: 'hub', n: n, since: (since.empty? ? nil : since))
          lines = logs.map { |doc| JSON.generate(doc) }
          respond(200, { engine: 'hub', count: lines.length, lines: lines })
        when ['requests']
          # Recent HTTP requests pulled from Mongo logs (preferred source)
          n = (req.params['n'] || '100').to_i
          since = (req.params['since'] || '').to_s
          docs = mongo_fetch_service(service_prefix: 'hub', n: n, since: (since.empty? ? nil : since))
          records = docs.select { |d| (d['event'] || d[:event]) == 'http_request' }.map do |d|
            h = d.is_a?(Hash) ? d : {}
            {
              id: h['_id'] || h['id'] || 0,
              time: h['timestamp'] || Time.now.utc.iso8601,
              method: h['method'] || 'GET',
              path: h['path'] || '/',
              query: h['query'] || nil,
              status: (h['status'] || 0).to_i,
              duration_ms: (h['duration_ms'] || 0).to_i,
              engine: h['service'] || 'hub',
              user: h['user'] || nil,
              request_body: h['request_body'] ? h['request_body'].to_s : nil,
              response_body: h['response_body'] ? h['response_body'].to_s : nil
            }
          end
          respond(200, { recent: records })
        else
          not_found
        end
      end

      # GET /logs -> aggregated last N events across engines from Mongo (polling)
      def logs_index(req)
        n = (req.params['n'] || '100').to_i
        mcp = (req.params['mcp'] || '').to_s
        since = (req.params['since'] || '').to_s
        type = (req.params['type'] || '').to_s
        events = mongo_fetch_aggregated(n: n, mcp: (mcp.empty? ? nil : mcp), since: (since.empty? ? nil : since))
        # Fallback to in-memory recorder if Mongo is unavailable or returned nothing
        if events.nil? || events.empty?
          events = recorder_fetch_aggregated(n: n, mcp: (mcp.empty? ? nil : mcp), since: (since.empty? ? nil : since))
        end
        if !type.empty? && type != 'all'
          events = events.select do |e|
            ev = e.is_a?(Hash) ? (e['event'] || e[:event]) : nil
            ev && ev.to_s == type
          end
        end
        respond(200, { count: events.length, events: events })
      end

      # GET /diagnostics/workflows -> recent workflow events
      def diagnostics_workflows(req)
        n = (req.params['n'] || '100').to_i
        events = @recorder.last(n, type: 'workflow_step')
        respond(200, { count: events.length, events: events })
      end

      # GET /diagnostics/workflow_runs -> saved runs summary
      # GET /diagnostics/workflow_runs -> saved runs summary
      def diagnostics_workflow_runs(_req)
        engine = workflow_engine
        respond(200, engine.runs_list)
      rescue StandardError => e
        respond(500, { error: 'workflow_runs_error', message: e.message })
      end

      def diagnostics_workflow_run(_req, workflow, run_id)
        engine = workflow_engine
        respond(200, engine.run_read(workflow: workflow, run_id: run_id))
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

      # Streaming removed for logs. Use polling endpoints instead.

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
          n = (req.params['n'] || '100').to_i
          since = (req.params['since'] || '').to_s
          logs = mongo_fetch_service(service_prefix: engine_name, n: n, since: (since.empty? ? nil : since))
          logs = recorder_fetch_service(service_prefix: engine_name, n: n, since: (since.empty? ? nil : since)) if logs.nil? || logs.empty?
          # Return as JSON lines for backwards compatibility with UI
          lines = logs.map { |doc| JSON.generate(doc) }
          respond(200, { engine: engine_name, count: lines.length, lines: lines })
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
          n = (req.params['n'] || '100').to_i
          since = (req.params['since'] || '').to_s
          logs = mongo_fetch_service(service_prefix: 'multiplexer', n: n, since: (since.empty? ? nil : since))
          logs = recorder_fetch_service(service_prefix: 'multiplexer', n: n, since: (since.empty? ? nil : since)) if logs.nil? || logs.empty?
          lines = logs.map { |doc| JSON.generate(doc) }
          respond(200, { engine: 'multiplexer', count: lines.length, lines: lines })
        else
          not_found
        end
      end

      # Fallback: aggregate recent events from in-memory recorder
      def recorder_fetch_aggregated(n:, mcp: nil, since: nil)
        rec = Savant::Logging::EventRecorder.global
        # Pull a reasonably large sample and filter
        arr = rec.last([n, 1000].max)
        arr = arr.select { |e| e[:mcp].to_s == mcp.to_s } if mcp
        t_since = parse_time_iso8601(since)
        if t_since
          arr = arr.select do |e|
            raw = e[:ts] || e[:timestamp]
            t = begin
              raw.is_a?(String) ? Time.parse(raw) : Time.at(raw.to_i)
            rescue StandardError
              nil
            end
            t && t > t_since
          end
        end
        # Normalize to Mongo-like docs
        docs = arr.map do |e|
          {
            'timestamp' => begin
              if e[:ts]
                e[:ts]
              elsif e[:timestamp]
                # seconds -> iso8601
                Time.at(e[:timestamp].to_i).utc.iso8601
              else
                Time.now.utc.iso8601
              end
            rescue StandardError
              Time.now.utc.iso8601
            end,
            'level' => (e[:level] || 'info'),
            'service' => (e[:mcp] || e[:service] || 'hub'),
            'event' => (e[:event] || e[:type] || 'event')
          }.merge(e)
        end
        docs.sort_by { |d| d['timestamp'].to_s }.reverse.first(n)
      end

      # Fallback: per-service logs from recorder
      def recorder_fetch_service(service_prefix:, n:, since: nil)
        rec = Savant::Logging::EventRecorder.global
        arr = rec.last([n, 1000].max)
        arr = arr.select do |e|
          svc = (e[:mcp] || e[:service] || '').to_s
          !!(svc =~ /^#{Regexp.escape(service_prefix)}(\.|$)/)
        end
        t_since = parse_time_iso8601(since)
        if t_since
          arr = arr.select do |e|
            raw = e[:ts] || e[:timestamp]
            t = begin
              raw.is_a?(String) ? Time.parse(raw) : Time.at(raw.to_i)
            rescue StandardError
              nil
            end
            t && t > t_since
          end
        end
        arr.map do |e|
          {
            'timestamp' => (e[:ts] || (Time.at(e[:timestamp].to_i).utc.iso8601 rescue Time.now.utc.iso8601)),
            'level' => (e[:level] || 'info'),
            'service' => (e[:mcp] || e[:service] || service_prefix),
            'event' => (e[:event] || e[:type] || 'event')
          }.merge(e)
        end.sort_by { |d| d['timestamp'].to_s }.reverse.first(n)
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
          version: Savant::VERSION,
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
              # Detailed per-table stats
              tables = %w[repos files blobs file_blob_map chunks personas rulesets agents agent_runs]
              details = []
              tables.each do |t|
                # Column presence
                cols = conn.exec_params("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=$1", [t]).map { |r| r['column_name'] }
                # Row count
                cnt = conn.exec("SELECT COUNT(*) AS c FROM #{t}")[0]['c'].to_i
                # Relation size in bytes
                sz = conn.exec_params('SELECT pg_total_relation_size($1::regclass) AS bytes', [t])[0]['bytes'].to_i
                # Last activity timestamp
                last_at = nil
                last_at = conn.exec("SELECT MAX(updated_at) AS m FROM #{t}")[0]['m'] if cols.include?('updated_at')
                last_at = conn.exec("SELECT MAX(created_at) AS m FROM #{t}")[0]['m'] if !last_at && cols.include?('created_at')
                details << { name: t, rows: cnt, size_bytes: sz, last_at: last_at }
              rescue StandardError => e
                details << { name: t, error: e.message }
              end
              db[:tables] = details
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

        # Reasoning API diagnostics (uptime/usage/agents)
        begin
          info[:reasoning] = build_reasoning_diagnostics
        rescue StandardError => e
          info[:reasoning] = { configured: false, error: e.message }
        end

        respond(200, info)
      end

      # GET /diagnostics/reasoning -> Reasoning API diagnostics only
      def diagnostics_reasoning(_req)
        begin
          data = build_reasoning_diagnostics
          return respond(200, data)
        rescue StandardError => e
          return respond(500, { configured: false, error: e.message })
        end
      end

      # DELETE /diagnostics/reasoning -> clear Reasoning activity (Mongo + in-memory)
      def diagnostics_reasoning_clear(_req)
        cleared = []
        errors = []

        # Best-effort: clear Mongo collections used by Reasoning
        begin
          if mongo_client
            %w[reasoning_logs reasoning_hooks_logs].each do |col_name|
              begin
                col = mongo_client[col_name]
                # Delete all docs without dropping collection (preserves indexes)
                res = col.delete_many({})
                cleared << { collection: col_name, deleted_count: (res.respond_to?(:deleted_count) ? res.deleted_count : nil) }
              rescue StandardError => e
                errors << { collection: col_name, error: e.message }
              end
            end
          end
        rescue StandardError => e
          errors << { step: 'mongo_clear', error: e.message }
        end

        # Best-effort: clear in-memory recorder events for reasoning
        begin
          @recorder.clear(mcp: 'reasoning') if @recorder.respond_to?(:clear)
        rescue StandardError
          # ignore
        end

        respond(200, { cleared: cleared, errors: errors, message: "Cleared Reasoning activity from #{cleared.length} collection(s)" })
      end

      # Helper: Build Reasoning diagnostics payload
      def build_reasoning_diagnostics
        reasoning = { configured: false }
        base_url = ENV['REASONING_API_URL'].to_s
        if !base_url.empty?
          reasoning[:configured] = true
          begin
            require 'uri'
            uri = URI.parse(base_url)
            if uri.host
              reasoning[:base_url] = "#{uri.scheme}://#{uri.host}#{(uri.port && ![80, 443].include?(uri.port)) ? ":#{uri.port}" : ''}"
            else
              reasoning[:base_url] = base_url
            end
          rescue StandardError
            reasoning[:base_url] = base_url
          end

          # Reachability probe with short timeouts
          begin
            require 'net/http'
            uri = URI.parse(base_url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = (uri.scheme == 'https')
            http.read_timeout = 1.5
            http.open_timeout = 1.5
            code = nil
            ['/healthz', '/health', '/version', uri.path.to_s, '/'].uniq.each do |p|
              next if p.nil? || p.to_s.empty?
              begin
                req = Net::HTTP::Get.new(p)
                resp = http.request(req)
                code = resp.code.to_i
                break if code && code > 0
              rescue StandardError
                # try next
              end
            end
            reasoning[:reachable] = !code.nil? && code < 500
            reasoning[:status_code] = code if code
          rescue StandardError => e
            reasoning[:reachable] = false
            reasoning[:error] = e.message
          end
        end

        # Usage stats via Mongo logs (service 'reasoning'); fallback to recorder if Mongo unavailable
        if mongo_client
          begin
            col = mongo_client['reasoning_logs']
            now = Time.now
            last_1h = now - 3600
            last_24h = now - 86_400
            calls_total = begin
              col.estimated_document_count
            rescue StandardError
              nil
            end
            calls_1h = begin
              col.count_documents({ 'timestamp' => { '$gt' => last_1h } })
            rescue StandardError
              nil
            end
            calls_24h = begin
              col.count_documents({ 'timestamp' => { '$gt' => last_24h } })
            rescue StandardError
              nil
            end
            last_at = begin
              doc = col.find({}, { sort: { timestamp: -1 }, projection: { timestamp: 1 } }).limit(1).first
              if doc && doc['timestamp']
                doc['timestamp'].respond_to?(:iso8601) ? doc['timestamp'].iso8601 : doc['timestamp'].to_s
              end
            rescue StandardError
              nil
            end
            events = %w[agent_intent workflow_intent reasoning_timeout reasoning_post_error]
            by_event = {}
            events.each do |ev|
              by_event[ev] = begin
                col.count_documents({ 'event' => ev })
              rescue StandardError
                nil
              end
            end
            reasoning[:calls] = { total: calls_total, last_1h: calls_1h, last_24h: calls_24h, last_at: last_at, by_event: by_event }
          rescue StandardError => e
            reasoning[:calls] = { error: e.message }
          end
        else
          # Recorder fallback: sample last 1000 events
          begin
            rec = Savant::Logging::EventRecorder.global
            arr = rec.last(1000, mcp: 'reasoning')
            now = Time.now
            last_1h = now - 3600
            last_24h = now - 86_400
            t_of = lambda do |e|
              raw = e[:ts] || e[:timestamp]
              begin
                raw.is_a?(String) ? Time.parse(raw) : Time.at(raw.to_i)
              rescue StandardError
                nil
              end
            end
            calls_total = arr.length
            calls_1h = arr.count { |e| (t = t_of.call(e)) && t > last_1h }
            calls_24h = arr.count { |e| (t = t_of.call(e)) && t > last_24h }
            last_at = begin
              t = arr.map { |e| t_of.call(e) }.compact.max
              t&.iso8601
            rescue StandardError
              nil
            end
            events = %w[agent_intent workflow_intent reasoning_timeout reasoning_post_error]
            by_event = {}
            events.each do |ev|
              by_event[ev] = arr.count { |e| (e[:event] || e['event']).to_s == ev }
            end
            reasoning[:calls] = { total: calls_total, last_1h: calls_1h, last_24h: calls_24h, last_at: last_at, by_event: by_event }
          rescue StandardError => e
            reasoning[:calls] = { error: e.message }
          end
        end

        # Agents and runs from Postgres (best-effort)
        begin
          agents_total = runs_total = runs_24h = nil
          last_run_at = nil
          if defined?(db_client) && db_client && db_client.table_exists?('agents')
            agents_total = db_client.exec('SELECT COUNT(*) AS c FROM agents')[0]['c'].to_i rescue nil
          end
          if defined?(db_client) && db_client && db_client.table_exists?('agent_runs')
            runs_total = db_client.exec('SELECT COUNT(*) AS c FROM agent_runs')[0]['c'].to_i rescue nil
            runs_24h = db_client.exec("SELECT COUNT(*) AS c FROM agent_runs WHERE created_at > NOW() - interval '24 hours'")[0]['c'].to_i rescue nil
            last_run_at = db_client.exec('SELECT MAX(created_at) AS m FROM agent_runs')[0]['m'] rescue nil
          end
          reasoning[:agents] = { total: agents_total, runs_total: runs_total, runs_24h: runs_24h, last_run_at: last_run_at }
        rescue StandardError => e
          reasoning[:agents] = { error: e.message }
        end

        reasoning
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
        # Skip CORS headers if rack-cors is handling it (e.g., under Rails)
        return {} if defined?(Rack::Cors)

        allow_origin = ENV['SAVANT_CORS_ORIGIN'] || '*'
        {
          'Access-Control-Allow-Origin' => allow_origin,
          'Access-Control-Allow-Headers' => 'content-type, x-savant-user-id',
          'Access-Control-Allow-Methods' => 'GET, POST, DELETE, OPTIONS'
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
          tool_candidates << t.tr('/', '_') if engine_name.to_s == 'context'
        rescue StandardError
          # ignore
        end
        tool_candidates = tool_candidates.uniq

        # Prefer registrar to pass user_id in ctx (enables per-user creds middleware)
        # Also log per-engine tool calls so /:engine/logs has content.
        logger = engine_logger_for(engine_name)

        last_error = nil
        tool_candidates.each do |name_variant|
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          logger&.info(event: 'tool.call start', name: name_variant, user: user_id)
          # Try registrar via specs (ensures load)
          begin
            manager.specs
            reg = manager.send(:registrar)
            result = reg.call(name_variant, params, ctx: { service: engine_name, engine: engine_name, user_id: user_id })
            dur = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
            logger&.info(event: 'tool.call finish', name: name_variant, duration_ms: dur)
            return result
          rescue StandardError => e
            # Record the last seen error to surface if no variant succeeds
            last_error = e
            # try next strategy
          end

          # Try public registrar accessor
          if manager.respond_to?(:registrar)
            begin
              result = manager.registrar.call(name_variant, params, ctx: { service: engine_name, engine: engine_name, user_id: user_id })
              dur = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
              logger&.info(event: 'tool.call finish', name: name_variant, duration_ms: dur)
              return result
            rescue StandardError => e
              last_error = e
              # Hot reload fallback
              begin
                result = hot_reload_and_call(engine_name, name_variant, params, user_id)
                dur = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
                logger&.info(event: 'tool.call finish', name: name_variant, duration_ms: dur)
                return result
              rescue StandardError => e2
                last_error = e2
                # try next candidate
              end
            end
          end

          # Last resort: use manager.call_tool
          begin
            result = manager.call_tool(name_variant, params)
            dur = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
            logger&.info(event: 'tool.call finish', name: name_variant, duration_ms: dur)
            return result
          rescue StandardError => e
            last_error = e
            begin
              result = hot_reload_and_call(engine_name, name_variant, params, user_id)
              dur = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
              logger&.info(event: 'tool.call finish', name: name_variant, duration_ms: dur)
              return result
            rescue StandardError => e2
              last_error = e2
              # continue loop
            end
          end
        end
        # All variants failed; surface the most recent error if available for better diagnostics
        raise(last_error || StandardError.new('Unknown tool'))
      end

      # Reuse a single file-backed logger per engine to avoid leaking file descriptors.
      def engine_logger_for(engine_name)
        return nil if engine_name.to_s.empty?
        @engine_loggers[engine_name] ||= begin
          path = log_path(engine_name)
          require_relative '../logging/logger'
          Savant::Logging::Logger.new(io: $stdout, file_path: path, json: true, service: engine_name)
        rescue StandardError
          nil
        end
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
        reg.call(tool, params, ctx: { service: engine_name, engine: engine_name, user_id: user_id })
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

      # DELETE /diagnostics/agent -> clear agent logs and session
      def diagnostics_agent_clear(_req)
        base = base_path
        session_path = File.join(base, '.savant', 'session.json')
        trace_path = File.join(base, 'logs', 'agent_trace.log')

        cleared = []
        errors = []

        # Clear session.json
        if File.file?(session_path)
          begin
            File.delete(session_path)
            cleared << 'session.json'
          rescue StandardError => e
            errors << { file: 'session.json', error: e.message }
          end
        end

        # Clear agent_trace.log
        if File.file?(trace_path)
          begin
            File.truncate(trace_path, 0)
            cleared << 'agent_trace.log'
          rescue StandardError => e
            errors << { file: 'agent_trace.log', error: e.message }
          end
        end

        # Also clear agent events from recorder
        begin
          @recorder.clear(type: 'reasoning_step') if @recorder.respond_to?(:clear)
        rescue StandardError
          # ignore if clear method not available
        end

        respond(200, { cleared: cleared, errors: errors, message: "Cleared #{cleared.length} file(s)" })
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
