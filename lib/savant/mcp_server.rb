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
      log.info("start: mode=stdio service=#{@service} tools=[fts/*, memory/*, fs/repo/*, jira_*]")
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
        require_relative 'context/tools'
        all_tools = []
        # Filter tools based on service type
        tools = case @service
                when 'jira' then Savant::Jira::Tools.specs
                when 'context' then Savant::Context::Tools.specs
                else all_tools
                end

        log.info("tools/list: service=#{@service} tool_count=#{tools.length}")
        response = { jsonrpc: '2.0', id: id, result: { tools: tools } }
        log.info("sending tools/list: response=#{response.to_json[0..100]}")
        puts(response.to_json)
        log.info("tools/list response sent")

      when 'tools/call'
        name = params['name']
        args = params['arguments'] or {}
        case @service
        when 'context'
          begin
            require_relative 'context/tools'
            @context_engine ||= Savant::Context::Engine.new
            data = Savant::Context::Tools.dispatch(@context_engine, name, args)
            content = [{ type: 'text', text: JSON.pretty_generate(data) }]
            puts({ jsonrpc: '2.0', id: id, result: { content: content } }.to_json)
          rescue Exception as e:
            code = -32006
            puts({ jsonrpc: '2.0', id: id, error: { code: code, message: str(e) } }.to_json)
          end
        when 'jira'
          begin
            require_relative 'jira/tools'
            @jira_engine ||= Savant::Jira.new
            data = Savant::Jira::Tools.dispatch(@jira_engine, name, args)
            content = [{ type: 'text', text: JSON.pretty_generate(data) }]
            puts({ jsonrpc: '2.0', id: id, result: { content: content } }.to_json)
          rescue Exception as e:
            puts({ jsonrpc: '2.0', id: id, error: { code: -32050, message: str(e) } }.to_json)
          end
        else
          puts({ jsonrpc: '2.0', id: id, error: { code: -32601, message: 'Unknown tool' } }.to_json)
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
