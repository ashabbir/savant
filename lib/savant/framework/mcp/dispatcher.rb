#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative '../../logging/logger'
require_relative '../../multiplexer'

module Savant
  module Framework
    module MCP
      # Dispatcher for JSON-RPC 2.0 requests targeting a single Savant service.
      # - Loads the requested service lazily.
      # - Validates and handles core MCP methods.
      # - Returns JSON strings (no direct IO) so transports can decide how to send.
      class Dispatcher
        def initialize(service:, log: Savant::Logging::Logger.new(io: $stdout, json: true, service: 'savant'), multiplexer: nil)
          @service = service.to_s
          @log = log
          @services = {}
          @multiplexer = multiplexer
        end

        # Parse and minimally validate a JSON-RPC 2.0 message string.
        # Returns [request_hash, error_json] where error_json is a string or nil.
        def parse(line)
          req = JSON.parse(line)
          unless req.is_a?(Hash) && req['jsonrpc'].to_s == '2.0' && req['method']
            return [nil,
                    json(response_error(nil,
                                        :invalid_request))]
          end

          @log.info(event: 'rpc_received', method: req['method'], id: req['id'], params: req['params']&.keys)
          [req, nil]
        rescue JSON::ParserError => e
          message = "parse_error: #{e.message} line=#{line[0..100]}"
          @log.error(event: 'parse_error', message: message)
          [nil, json(response_error(nil, :parse_error, message: message))]
        end

        # Handle a parsed JSON-RPC request and return a JSON string response.
        def handle(req)
          id = req['id']
          method = req['method']
          params = req['params'] || {}

          return handle_multiplexer(req) if @multiplexer

          case method
          when 'initialize'
            begin
              svc = load_service(@service)
              info = if svc[:engine].respond_to?(:server_info)
                       svc[:engine].server_info
                     else
                       { name: 'savant', version: '1.1.0', description: "Savant MCP service=#{@service}" }
                     end
              tool_count = svc[:registrar].specs.length
              instructions = info[:description] || "Savant MCP service=#{@service} tools=#{tool_count}"
              server_info = { name: info[:name] || 'savant', version: info[:version] || '1.1.0' }
            rescue StandardError
              instructions = "Savant MCP service=#{@service} (unavailable)"
              server_info = { name: 'savant', version: '1.1.0' }
            end
            result = {
              protocolVersion: '2024-11-05',
              serverInfo: server_info,
              capabilities: { tools: {} },
              instructions: instructions
            }
            json(response_ok(id, result))
          when 'tools/list'
            svc = load_service(@service)
            tools_list = svc[:registrar].specs
            json(response_ok(id, { tools: tools_list }))
          when 'tools/call'
          name = normalize_tool_name(params['name'])
            args = params['arguments'] || {}
            begin
              svc = load_service(@service)
              ctx = { engine: svc[:engine], request_id: id, service: @service, logger: Savant::Logging::Logger.new(io: $stdout, json: true, service: @service) }
              # Provide composition API: ctx.invoke(name, args) and ctx[:invoke]
              invoker = proc { |nm, a| svc[:registrar].call(nm, a, ctx: ctx) }
              ctx[:invoke] = invoker
              begin
                ctx.define_singleton_method(:invoke) { |nm, a| invoker.call(nm, a) }
              rescue TypeError
                # If ctx is frozen or doesn't accept singleton methods, ignore.
              end
            data = svc[:registrar].call(name, args, ctx: ctx)
              content = [{ type: 'text', text: JSON.pretty_generate(data) }]
              json(response_ok(id, { content: content }))
            rescue StandardError => e
              @log.error(event: 'tool_error', tool: name, message: e.message)
              json(response_error(id, :internal_error, message: e.message))
            end
          else
            json(response_error(id, :method_not_found))
          end
        rescue StandardError => e
          json(response_error(req['id'], :internal_error, message: e.message))
        end

        private

        def handle_multiplexer(req)
          id = req['id']
          method = req['method']
          params = req['params'] || {}

          case method
          when 'initialize'
            json(response_ok(id, @multiplexer.server_info))
          when 'tools/list'
            json(response_ok(id, { tools: @multiplexer.tools }))
          when 'tools/call'
            name = params['name']
            args = params['arguments'] || {}
            result = @multiplexer.call(name, args)
            json(response_ok(id, result))
          else
            json(response_error(id, :method_not_found))
          end
        rescue Savant::Multiplexer::ToolNotFound => e
          json(response_error(id, :method_not_found, message: e.message))
        rescue Savant::Multiplexer::EngineOffline => e
          json(response_error(id, :internal_error, message: e.message))
        rescue StandardError => e
          json(response_error(id, :internal_error, message: e.message))
        end

        def json(obj) = JSON.generate(obj)

        def error_catalog
          {
            parse_error: { code: -32_700, message: 'Parse error' },
            invalid_request: { code: -32_600, message: 'Invalid Request' },
            method_not_found: { code: -32_601, message: 'Method not found' },
            invalid_params: { code: -32_602, message: 'Invalid params' },
            internal_error: { code: -32_000, message: 'Internal error' }
          }
        end

        def response_ok(id, result)
          { jsonrpc: '2.0', id: id, result: result }
        end

        def response_error(id, key, message: nil)
          spec = error_catalog[key] || error_catalog[:internal_error]
          { jsonrpc: '2.0', id: id, error: { code: spec[:code], message: message || spec[:message] } }
        end

        # Load a service by convention (e.g., context -> Savant::Context::{Engine,Tools})
        def normalize_tool_name(name)
          return name unless name.is_a?(String)
          normalized = name.tr('./', '_')
          normalized.gsub(/_{2,}/, '_')
        end

        def load_service(name)
          key = name.to_s
          return @services[key] if @services[key]

          camel = key.split(/[^a-zA-Z0-9]/).map { |s| s[0] ? s[0].upcase + s[1..] : '' }.join
          require File.expand_path(File.join(__dir__, '..', '..', 'engines', key, 'engine'))
          require File.expand_path(File.join(__dir__, '..', '..', 'engines', key, 'tools'))

          mod = Savant.const_get(camel)
          engine_class = mod.const_get(:Engine)
          tools_mod = mod.const_get(:Tools)
          engine = engine_class.new
          registrar = tools_mod.build_registrar(engine)
          # Inject framework lifecycle hooks as a middleware if the engine
          # supports wrap_call (Savant::Framework::Engine::Base or compatible API).
          if engine.respond_to?(:wrap_call)
            registrar.use_middleware do |ctx, nm, a, nxt|
              engine.wrap_call(ctx, nm, a) { nxt.call(ctx, nm, a) }
            end
          end
          @services[key] = { engine: engine, registrar: registrar }
        rescue LoadError, NameError
          raise 'Unknown service'
        end
      end
    end
  end
end
