#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

module Savant
  module MCP
    # HTTP adapter that handles MCP JSON-RPC over HTTP for hub-mounted engines.
    # It translates JSON-RPC methods (initialize, tools/list, tools/call, ping)
    # into calls against a provided ServiceManager and returns JSON-RPC 2.0
    # response envelopes.
    class HttpAdapter
      def initialize(manager:, engine_name:, user_id: nil, logger: nil)
        @manager = manager
        @engine_name = engine_name
        @user_id = user_id
        @logger = logger
      end

      def handle(raw_body)
        req = parse_request(raw_body)
        method = req[:method]
        id = req[:id]
        params = req[:params] || {}

        case method
        when 'initialize'
          json_ok(id, initialize_payload)
        when 'tools/list'
          tools = safe_specs
          json_ok(id, { tools: tools })
        when 'tools/call'
          name = params['name']
          args = params['arguments'] || {}
          data = call_tool(name, args, request_id: id)
          content = [{ type: 'text', text: JSON.pretty_generate(data) }]
          json_ok(id, { content: content })
        when 'ping'
          json_ok(id, { ok: true })
        else
          json_error(id, -32_601, 'Method not found')
        end
      rescue JSON::ParserError => e
        json_error(nil, -32_700, "Parse error: #{e.message}")
      rescue ArgumentError => e
        json_error(nil, -32_600, e.message)
      rescue StandardError => e
        log(:error, 'mcp_http.internal_error', error: e, method: (defined?(method) ? method : nil))
        json_error(req_id_or_nil(raw_body), -32_000, 'Internal error')
      end

      private

      attr_reader :manager, :engine_name, :user_id, :logger

      def parse_request(raw)
        raise JSON::ParserError, 'Empty request body' if raw.nil? || raw.empty?

        data = JSON.parse(raw)
        raise ArgumentError, 'Invalid Request' unless data.is_a?(Hash) && data['method']

        { id: data['id'], method: data['method'], params: data['params'] || {} }
      end

      def initialize_payload
        info = begin
          manager.service_info
        rescue StandardError
          { name: 'savant', version: '1.1.0', description: "Savant MCP service=#{engine_name} (unavailable)" }
        end
        tool_count = begin
          safe_specs.length
        rescue StandardError
          0
        end
        instructions = info[:description] || "Savant MCP service=#{engine_name} tools=#{tool_count}"
        server_info = { name: info[:name] || 'savant', version: info[:version] || '1.1.0' }
        {
          protocolVersion: '2024-11-05',
          serverInfo: server_info,
          capabilities: { tools: {} },
          instructions: instructions
        }
      end

      def safe_specs
        # Avoid instantiating engines twice; prefer manager.specs if available
        return manager.specs if manager.respond_to?(:specs)

        # Fallback: try to access registrar to fetch specs
        if manager.respond_to?(:registrar)
          reg = manager.registrar
          return reg.specs if reg.respond_to?(:specs)
        end
        []
      rescue StandardError
        []
      end

      def call_tool(name, args, request_id: nil)
        # Prefer direct registrar access to inject user context (as router does)
        if manager.respond_to?(:registrar)
          begin
            reg = manager.registrar
            return reg.call(name.to_s, args, ctx: { engine: engine_name, user_id: user_id })
          rescue StandardError
            # fall through to generic path
          end
        end
        # Generic path via ServiceManager API
        manager.call_tool(name.to_s, args, request_id: request_id)
      end

      def json_ok(id, result)
        { jsonrpc: '2.0', id: id, result: result, error: nil }
      end

      def json_error(id, code, message)
        { jsonrpc: '2.0', id: id, result: nil, error: { code: code, message: message } }
      end

      def log(level, message, meta = {})
        return unless logger

        parts = [message]
        meta.each { |k, v| parts << "#{k}=#{format_value(v)}" }
        logger.public_send(level, parts.join(' '))
      end

      def format_value(value)
        value.is_a?(StandardError) ? "#{value.class}: #{value.message}" : value
      end

      def req_id_or_nil(raw)
        JSON.parse(raw)['id']
      rescue StandardError
        nil
      end
    end
  end
end
