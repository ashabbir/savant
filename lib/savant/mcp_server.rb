#!/usr/bin/env ruby
#
# Purpose: Stdio JSON‑RPC 2.0 server for MCP services.
#
# Selects the active service via `MCP_SERVICE` (e.g., 'context' or 'jira'),
# advertises its tools, and dispatches tool calls to the service Engine. Logs
# to `logs/<service>.log` and keeps stdout/stderr synchronized for MCP clients.

require 'json'
require 'securerandom'
require_relative 'logger'
require 'fileutils'

module Savant
  # JSON‑RPC 2.0 stdio MCP server hosting a single service per process.
  #
  # Purpose: Bridge editors (via MCP) to Savant tools. Selects the active
  # service using `MCP_SERVICE` (e.g., `context`, `jira`), advertises that
  # service's tools, and delegates `tools/call` to the corresponding engine.
  class MCPServer
    def initialize(host: nil, port: nil)
      default_settings = File.join((ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty? ? ENV['SAVANT_PATH'] : File.expand_path('../../..', __dir__)), 'config', 'settings.json'); settings_path = default_settings
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
      log.info("start: mode=stdio service=#{@service} tools=loading")
      log.info("pwd=#{Dir.pwd}")
      log.info("settings_path=#{settings_path}")
      log.info("log_path=#{log_path}")
      # Build engine + registrar once per service
      @context_engine = nil
      @context_registrar = nil
      @jira_engine = nil
      @jira_registrar = nil

      STDOUT.sync = true
      STDERR.sync = true
      STDIN.sync = true

      log.info("buffers synced, waiting for requests...")
      log.info("=" * 80) 
      # JSON-RPC 2.0 MCP only (legacy disabled)
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

        log.info("handeling jsonrpc request")
        handle_jsonrpc(req, search, jira, log)
        log.info("handeled jsonrpc request")
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
        instructions = case @service
                       when 'jira' then 'Savant provides Jira tools via registrar.'
                       when 'context' then 'Savant provides Context tools via registrar.'
                       else "Savant is running with service=#{@service}; no tools registered."
                       end
        result = {
          protocolVersion: '2024-11-05',
          serverInfo: { name: 'savant', version: '1.0.0' },
          capabilities: { tools: {} },
          instructions: instructions
        }
        response = { jsonrpc: '2.0', id: id, result: result }
        log.info("sending initialize response: #{response.to_json[0..100]}")
        puts response.to_json
        log.info("initialize response sent")

      when 'tools/list'
        require_relative 'jira/tools'
        require_relative 'jira/engine'
        require_relative 'context/tools'
        require_relative 'context/engine'
        # Lazily construct engine + registrar
        tools_list = case @service
                     when 'jira'
                       @jira_engine ||= Savant::Jira::Engine.new
                       @jira_registrar ||= Savant::Jira::Tools.build_registrar(@jira_engine)
                       @jira_registrar.specs
                     when 'context'
                       @context_engine ||= Savant::Context::Engine.new
                       @context_registrar ||= Savant::Context::Tools.build_registrar(@context_engine)
                       @context_registrar.specs
                     else
                       []
                     end

        log.info("tools/list: service=#{@service} tool_count=#{tools_list.length}")
        response = { jsonrpc: '2.0', id: id, result: { tools: tools_list } }
        log.info("sending tools/list: response=#{response.to_json[0..100]}")
        puts(response.to_json)
        log.info("tools/list response sent")

      when 'tools/call'
        name = params['name']
        args = params['arguments'] || {}
        begin
          case @service
          when 'context'
            require_relative 'context/tools'
            require_relative 'context/engine'
            @context_engine ||= Savant::Context::Engine.new
            @context_registrar ||= Savant::Context::Tools.build_registrar(@context_engine)
            data = @context_registrar.call(name, args, ctx: { engine: @context_engine, request_id: id })
          when 'jira'
            require_relative 'jira/tools'
            require_relative 'jira/engine'
            @jira_engine ||= Savant::Jira::Engine.new
            @jira_registrar ||= Savant::Jira::Tools.build_registrar(@jira_engine)
            data = @jira_registrar.call(name, args, ctx: { engine: @jira_engine, request_id: id })
          else
            raise 'Unknown service'
          end
          content = [{ type: 'text', text: JSON.pretty_generate(data) }]
          puts({ jsonrpc: '2.0', id: id, result: { content: content } }.to_json)
        rescue => e
          code = (@service == 'jira') ? -32050 : -32000
          puts({ jsonrpc: '2.0', id: id, error: { code: code, message: e.message } }.to_json)
        end
      else
        puts({ jsonrpc: '2.0', id: id, error: { code: -32601, message: 'Method not found' } }.to_json)
      end
    rescue => e
      puts({ jsonrpc: '2.0', id: req['id'], error: { code: -32000, message: e.message } }.to_json)
    end

    # legacy handler removed
  end
end
