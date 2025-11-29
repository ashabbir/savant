# frozen_string_literal: true

require 'json'
require 'rack/request'

require_relative '../../service_manager'

module Savant
  module Transports
    module HTTP
      # Minimal Rack app exposing Savant tools via JSON-RPC over HTTP.
      class RackApp
        def self.build(service_manager:, logger: nil)
          new(service_manager: service_manager, logger: logger)
        end

        def initialize(service_manager:, logger: nil)
          @service_manager = service_manager
          @logger = logger
        end

        def call(env)
          request = Rack::Request.new(env)
          case [request.request_method, request.path_info]
          when ['GET', '/healthz']
            respond_json(200, { status: 'ok', service: 'savant-http' })
          when ['POST', '/rpc']
            handle_rpc(request)
          else
            respond_json(404, json_error(nil, -32_601, 'Not Found'))
          end
        end

        private

        attr_reader :service_manager, :logger

        def handle_rpc(request)
          status, body = with_payload(request) do |payload|
            result = service_manager.call_tool(payload[:method], payload[:params], request_id: payload[:id])
            log(:info, 'response.success', id: payload[:id], method: payload[:method])
            [200, json_ok(payload[:id], result)]
          end
          respond_json(status, body)
        end

        def read_body(request)
          request.body.rewind if request.body.respond_to?(:rewind)
          data = request.body.read.to_s
          request.body.rewind if request.body.respond_to?(:rewind)
          data
        end

        def parse_payload(raw)
          raise JSON::ParserError, 'Empty request body' if raw.nil? || raw.empty?

          JSON.parse(raw)
        end

        def validate_payload!(payload)
          raise Savant::BadRequestError, 'Invalid Request' unless payload.is_a?(Hash) && payload['method']
        end

        def payload_id(payload)
          return nil if payload.nil?

          payload.is_a?(Hash) ? (payload[:id] || payload['id']) : nil
        end

        def respond_json(status, body_hash)
          [status, { 'Content-Type' => 'application/json' }, [JSON.generate(body_hash)]]
        end

        def json_ok(id, result) = { jsonrpc: '2.0', id: id, result: result, error: nil }

        def json_error(id, code, message)
          { jsonrpc: '2.0', id: id, result: nil, error: { code: code, message: message } }
        end

        def log(level, message, meta = {})
          return unless logger

          parts = [message]
          meta.each { |key, value| parts << "#{key}=#{format_value(value)}" }
          logger.public_send(level, parts.join(' '))
        end

        def format_value(value) = value.is_a?(StandardError) ? "#{value.class}: #{value.message}" : value

        def preview(body)
          return '' if body.nil? || body.empty?

          body.length > 200 ? "#{body[0, 200]}…" : body
        end

        def parse_rpc_request(request)
          raw = read_body(request)
          log(:info, 'request.received', body_preview: preview(raw), path: request.path_info)
          data = parse_payload(raw)
          payload = {
            id: data.is_a?(Hash) ? data['id'] : nil,
            method: data.is_a?(Hash) ? data['method'] : nil,
            params: data.is_a?(Hash) ? (data['params'] || {}) : {}
          }
          validate_payload!(data)
          payload
        end

        def with_payload(request)
          payload = nil
          payload = parse_rpc_request(request)
          yield(payload)
        rescue StandardError => e
          status, body, level, tag = payload_error_response(e, payload)
          log(level, tag, error: e, id: payload_id(payload))
          [status, body]
        end

        def payload_error_response(error, payload)
          id = payload_id(payload)
          case error
          when JSON::ParserError then parse_error_response(error)
          when Savant::BadRequestError then [400, json_error(id, -32_600, error.message), :warn, 'request.invalid']
          when Savant::UnknownServiceError then [404, json_error(id, -32_601, error.message), :error, 'service.unknown']
          else [500, json_error(id, -32_000, 'Internal error'), :error, 'response.error']
          end
        end

        def parse_error_response(error)
          message = "Parse error: #{error.message}"
          [400, json_error(nil, -32_700, message), :error, 'request.parse_error']
        end
      end
    end
  end
end
