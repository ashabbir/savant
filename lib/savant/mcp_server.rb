require 'json'
require 'securerandom'
require_relative 'logger'
require 'fileutils'

module Savant
  class MCPServer
    def initialize(host: nil, port: nil)
      settings_path = ENV['SETTINGS_PATH'] || 'config/settings.json'
      cfg = JSON.parse(File.read(settings_path)) rescue {}
      which = (ENV['MCP_SERVICE'] || 'context').to_s
      mcp_cfg = cfg.dig('mcp', which) || {}
      host ||= ENV['LISTEN_HOST'] || mcp_cfg['listenHost'] || '0.0.0.0'
      port ||= Integer(ENV['LISTEN_PORT'] || mcp_cfg['listenPort'] || (which == 'jira' ? 8766 : 8765))
      @host = host
      @port = port
      @service = which
    end

    def start
      # Determine Savant base path from ENV or infer from current file path
      base_path = (ENV['SAVANT_PATH'] || '').to_s.strip
      if base_path.empty?
        # Fallback: repo root relative to this file (lib/savant/... -> project root)
        base_path = File.expand_path('../../..', __dir__)
      end

      # Compute paths and ensure logs directory exists
      settings_path = File.join(base_path, 'config', 'settings.json')
      log_dir = File.join(base_path, 'logs')
      FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)
      log_path = File.join(log_dir, "#{@service}.log")

      # File-backed logger
      log_io = File.open(log_path, 'a')
      log_io.sync = true
      log = Savant::Logger.new(component: 'mcp', out: log_io)
      log.info("=" * 80)
      log.info("start: mode=stdio service=#{@service} tools=[search,jira_search,jira_self]")
      log.info("pwd=#{Dir.pwd}")
      log.info("settings_path=#{settings_path}")
      log.info("log_path=#{log_path}")
      search = nil
      jira = nil

      STDOUT.sync = true
      STDERR.sync = true
      STDIN.sync = true

      log.info("buffers synced, waiting for requests...")
      log.info("=" * 80) 
      # JSON-RPC 2.0 MCP minimal implementation with legacy fallback
      while (line = STDIN.gets)
        log.info("raw_input: #{line.strip[0..200]}")
        begin
          req = JSON.parse(line)
          log.info("received: method;#{req['method']} id=#{req['id']} params=#{req['params']&.keys}")
        rescue JSON::ParserError => e
          message = "parse_error: #{e.message} line=#{line[0..100]}"
          log.error(message)
          STDERR.puts({ jsonrpc: '2.0', error: { code: -32700, message: message } }.to_json)
          next
        end

        if req.is_a?(Hash) && req.key?('method')
          log.info("handeling jsonrpc request")
          handle_jsonrpc(req, search, jira, log)
          log.info("handeled jsonrpc request")
        else
          log.info("handeling legacy request")
          handle_legacy(req, search, jira, log)
          log.info("handeled jsonrpc request")
        end
      end
    rescue Interrupt
      log = Savant::Logger.new(component: 'mcp')
      log.info('shutdown from Interrupt')
    end

    private

    def handle_jsonrpc(req, search, jira, log)
      id = req['id']
      method = req['method']
      params = req['params'] || {}

      case method
      when 'initialize'
        result = {
          protocolVersion: '2024-11-05',
          serverInfo: { name: 'savant', version: '1.0.0' },
          capabilities: { tools: {} },
          instructions: 'Savant provides tools: search, jira_search, jira_self.'
        }
        response = { jsonrpc: '2.0', id: id, result: result }
        log.info("sending initialize response: #{response.to_json[0..100]}")
        puts response.to_json
        log.info("initialize response sent")

      when 'tools/list'
        all_tools = [
          {
            name: 'search',
            description: 'Full‑text search over indexed repos',
            inputSchema: {
              type: 'object',
              properties: {
                q: { type: 'string' },
                repo: { anyOf: [{ type: 'string' }, { type: 'null' }] },
                limit: { type: 'integer', minimum: 1, maximum: 100 }
              },
              required: ['q']
            }
          },
          {
            name: 'jira_search',
            description: 'Run a Jira JQL search',
            inputSchema: {
              type: 'object',
              properties: {
                jql: { type: 'string' },
                limit: { type: 'integer', minimum: 1, maximum: 100 },
                start_at: { type: 'integer', minimum: 0 }
              },
              required: ['jql']
            }
          },
          {
            name: 'jira_self',
            description: 'Verify Jira credentials',
            inputSchema: { type: 'object', properties: {} }
          }
        ]
        # Filter tools based on service type
        tools = if @service == 'jira'
          all_tools.select { |t| t[:name].to_s.start_with?('jira') }
        else
          all_tools.select { |t| t[:name].to_s.start_with?('search') }
        end

        log.info("tools/list: service=#{@service} tool_count=#{tools.length}")
        response = { jsonrpc: '2.0', id: id, result: { tools: tools } }
        log.info("sending tools/list: response=#{response.to_json[0..100]}")
        puts(response.to_json)
        log.info("tools/list response sent")

      when 'tools/call'
        name = params['name']
        args = params['arguments'] || {}
        case name
        when 'search'
          q = (args['q'] || '').to_s
          repo = args.key?('repo') ? args['repo'] : nil
          limit = Integer(args['limit'] || 10) rescue 10
          data, took_ms = log.with_timing {
            require_relative 'search' unless defined?(Savant::Search)
            (search ||= Savant::Search.new).search(q: q, repo: repo, limit: limit)
          }
          content = [{ type: 'text', text: JSON.pretty_generate(data) }]
          puts({ jsonrpc: '2.0', id: id, result: { content: content } }.to_json)
        when 'jira_search'
          begin
            require_relative 'jira' unless defined?(Savant::Jira)
            jira ||= Savant::Jira.new
          rescue => e
            error = { code: -32001, message: 'jira disabled: missing config' }
            puts({ jsonrpc: '2.0', id: id, error: error }.to_json)
            return
          end
            jql = (args['jql'] || '').to_s
            limit = Integer(args['limit'] || 10) rescue 10
            start_at = Integer(args['start_at'] || 0) rescue 0
            data, _ms = log.with_timing { jira.search(jql: jql, limit: limit, start_at: start_at) }
            content = [{ type: 'text', text: JSON.pretty_generate(data) }]
            puts({ jsonrpc: '2.0', id: id, result: { content: content } }.to_json)
        when 'jira_self'
          begin
            require_relative 'jira' unless defined?(Savant::Jira)
            jira ||= Savant::Jira.new
          rescue => e
            error = { code: -32001, message: 'jira disabled: missing config' }
            puts({ jsonrpc: '2.0', id: id, error: error }.to_json)
            return
          end
          data, _ms = log.with_timing { jira.self_test }
          content = [{ type: 'text', text: JSON.pretty_generate(data) }]
          puts({ jsonrpc: '2.0', id: id, result: { content: content } }.to_json)
        else
          puts({ jsonrpc: '2.0', id: id, error: { code: -32601, message: 'Unknown tool' } }.to_json)
        end
      else
        puts({ jsonrpc: '2.0', id: id, error: { code: -32601, message: 'Method not found' } }.to_json)
      end
    rescue => e
      puts({ jsonrpc: '2.0', id: req['id'], error: { code: -32000, message: e.message } }.to_json)
    end

    def handle_legacy(req, search, jira, log)
      rid = (req['id'] || SecureRandom.hex(6)).to_s rescue SecureRandom.hex(6)
      case req['tool']
      when 'search'
        require_relative 'search' unless defined?(Savant::Search)
        search ||= Savant::Search.new
        out, exec_ms = log.with_timing { search.search(q: req['q'].to_s, repo: req['repo'], limit: (req['limit'] || 10).to_i) }
        log.info("legacy: search ok dur=#{exec_ms}ms id=#{rid}")
        puts({ ok: true, data: out, id: rid }.to_json)
      when 'jira_search'
        begin
          require_relative 'jira' unless defined?(Savant::Jira)
          jira ||= Savant::Jira.new
        rescue => e
          puts({ ok: false, error: 'jira disabled: missing config', id: rid }.to_json)
          return
        end
          out, exec_ms = log.with_timing { jira.search(jql: req['jql'].to_s, limit: (req['limit'] || 10).to_i, start_at: (req['start_at'] || 0).to_i) }
          log.info("legacy: jira_search ok dur=#{exec_ms}ms id=#{rid}")
          puts({ ok: true, data: out, id: rid }.to_json)
      when 'jira_self'
        begin
          require_relative 'jira' unless defined?(Savant::Jira)
          jira ||= Savant::Jira.new
        rescue => e
          puts({ ok: false, error: 'jira disabled: missing config', id: rid }.to_json)
          return
        end
          out, exec_ms = log.with_timing { jira.self_test }
          log.info("legacy: jira_self ok dur=#{exec_ms}ms id=#{rid}")
          puts({ ok: true, data: out, id: rid }.to_json)
      else
        puts({ ok: false, error: 'unknown tool', id: rid }.to_json)
      end
    end
  end
end
