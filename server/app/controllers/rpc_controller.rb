# frozen_string_literal: true

class RpcController < ApplicationController
  rescue_from JSON::ParserError do |e|
    render json: json_error(nil, -32_700, "Parse error: #{e.message}"), status: :bad_request
  end

  def healthz
    render json: { status: 'ok', service: 'savant-rails' }
  end

  def call
    payload = parse_payload
    engine, tool = split_method(payload[:method])
    mgr = Savant::Hub::ServiceManager.new(service: engine)
    result = mgr.call_tool(tool, payload[:params], request_id: payload[:id])
    render json: json_ok(payload[:id], result)
  rescue Savant::Hub::BadRequestError => e
    render json: json_error(payload_id, -32_600, e.message), status: :bad_request
  rescue Savant::Hub::UnknownServiceError => e
    render json: json_error(payload_id, -32_601, e.message), status: :not_found
  rescue StandardError
    render json: json_error(payload_id, -32_000, 'Internal error'), status: :internal_server_error
  end

  private

  def split_method(method)
    parts = method.to_s.split('.', 2)
    raise Savant::Hub::BadRequestError, 'Invalid method' unless parts.length == 2
    [parts[0], parts[1]]
  end

  def parse_payload
    raw = request.raw_post.to_s
    raise JSON::ParserError, 'Empty request body' if raw.empty?
    json = JSON.parse(raw)
    method = json.is_a?(Hash) ? json['method'] : nil
    raise Savant::Hub::BadRequestError, 'Invalid Request' unless method
    {
      id: json['id'],
      method: method,
      params: json['params'] || {}
    }
  end

  def payload_id
    @payload&.dig(:id)
  end

  def json_ok(id, result)
    { jsonrpc: '2.0', id: id, result: result, error: nil }
  end

  def json_error(id, code, message)
    { jsonrpc: '2.0', id: id, result: nil, error: { code: code, message: message } }
  end
end
