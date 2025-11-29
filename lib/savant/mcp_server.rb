#!/usr/bin/env ruby
# frozen_string_literal: true

# !
# Purpose: Transport-agnostic launcher for MCP services.
#
# Selects the active service via `MCP_SERVICE` (e.g., 'context' or 'jira'), and
# starts either stdio or websocket transport based on config/flags.

require_relative 'transports/mcp/stdio'
require_relative 'transports/mcp/websocket'
require_relative 'config'

module Savant
  # Launch MCP with selected transport.
  class MCPServer
    def initialize(transport: nil, host: nil, port: nil, path: nil)
      @service = (ENV['MCP_SERVICE'] || 'context').to_s
      base = (if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
                ENV['SAVANT_PATH']
              else
                File.expand_path('../../..', __dir__)
              end)
      settings_path = File.join(base, 'config', 'settings.json')

      cfg = begin
        Savant::Config.load(settings_path)
      rescue StandardError
        {}
      end

      # Determine transport mode from arg, env, or config
      @transport_mode = (transport || ENV['TRANSPORT'] || cfg.dig('transport', 'mode') || 'stdio').to_s
      ws_cfg = cfg.dig('transport', 'websocket') || {}
      @ws_host = host || ws_cfg['host'] || '127.0.0.1'
      @ws_port = Integer(port || ws_cfg['port'] || 8765)
      @ws_path = path || ws_cfg['path'] || '/mcp'
    end

    def start
      case @transport_mode
      when 'websocket'
        Savant::Transports::MCP::WebSocket.new(service: @service, host: @ws_host, port: @ws_port, path: @ws_path).start
      else
        Savant::Transports::MCP::Stdio.new(service: @service).start
      end
    end
  end
end
