# frozen_string_literal: true

require 'json'
require 'rack/mock'

require_relative '../../../lib/savant/transports/http/rack_app'

NullLogger = Class.new do
  def info(*) = nil
  def warn(*) = nil
  def error(*) = nil
end

module SavantTransportHttpSpec
  class EchoManager
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call_tool(name, params, request_id: nil)
      @calls << { name: name, params: params, request_id: request_id }
      { 'ok' => true, 'echo' => params }
    end

    def service = 'context'
    def service_info = { name: 'test', version: '1.0.0' }
  end

  class PassthroughManager
    def call_tool(*) = { 'ok' => true }
    def service = 'context'
    def service_info = { name: 'test', version: '1.0.0' }
  end

  class RaisingManager
    def call_tool(*) = raise(StandardError, 'boom')
    def service = 'context'
    def service_info = { name: 'test', version: '1.0.0' }
  end

  def self.build_request(service_manager, logger)
    app = Savant::Transports::HTTP::RackApp.build(service_manager: service_manager, logger: logger)
    Rack::MockRequest.new(app)
  end
end

RSpec.describe Savant::Transports::HTTP::RackApp, 'POST /rpc success' do
  let(:logger) { NullLogger.new }
  let(:service_manager) { SavantTransportHttpSpec::EchoManager.new }

  let(:request) do
    app = described_class.build(service_manager: service_manager, logger: logger)
    Rack::MockRequest.new(app)
  end

  it 'returns JSON-RPC response when tool succeeds' do
    payload = { method: 'test.echo', params: { 'msg' => 'hi' }, id: 'abc123' }
    response = request.post('/rpc', 'CONTENT_TYPE' => 'application/json', input: JSON.generate(payload))

    expect(response.status).to eq(200)
    body = JSON.parse(response.body)
    expect(body['result']).to eq({ 'ok' => true, 'echo' => { 'msg' => 'hi' } })
    expect(body['error']).to be_nil
    expect(body['id']).to eq('abc123')
  end
end

RSpec.describe Savant::Transports::HTTP::RackApp, 'POST /rpc parse error' do
  let(:logger) { NullLogger.new }

  it 'returns parse error payload on invalid JSON' do
    request = SavantTransportHttpSpec.build_request(SavantTransportHttpSpec::PassthroughManager.new, logger)
    response = request.post('/rpc', 'CONTENT_TYPE' => 'application/json', input: '{bad-json')

    expect(response.status).to eq(400)
    body = JSON.parse(response.body)
    expect(body['error']['code']).to eq(-32_700)
  end
end

RSpec.describe Savant::Transports::HTTP::RackApp, 'POST /rpc invalid request' do
  let(:logger) { NullLogger.new }

  it 'returns invalid request error when method missing' do
    payload = { params: { foo: 'bar' }, id: 1 }
    request = SavantTransportHttpSpec.build_request(SavantTransportHttpSpec::PassthroughManager.new, logger)
    response = request.post('/rpc', 'CONTENT_TYPE' => 'application/json', input: JSON.generate(payload))

    expect(response.status).to eq(400)
    body = JSON.parse(response.body)
    expect(body['error']['code']).to eq(-32_600)
  end
end

RSpec.describe Savant::Transports::HTTP::RackApp, 'POST /rpc internal error' do
  let(:logger) { NullLogger.new }

  it 'returns internal error payload when tool fails' do
    payload = { method: 'test.boom', params: {}, id: 'err-1' }
    request = SavantTransportHttpSpec.build_request(SavantTransportHttpSpec::RaisingManager.new, logger)
    response = request.post('/rpc', 'CONTENT_TYPE' => 'application/json', input: JSON.generate(payload))

    expect(response.status).to eq(500)
    body = JSON.parse(response.body)
    expect(body['error']['code']).to eq(-32_000)
    expect(body['error']['message']).to eq('Internal error')
  end
end

RSpec.describe Savant::Transports::HTTP::RackApp, 'GET /healthz' do
  let(:logger) { NullLogger.new }
  let(:service_manager) { SavantTransportHttpSpec::PassthroughManager.new }

  let(:request) do
    app = Savant::Transports::HTTP::RackApp.build(service_manager: service_manager, logger: logger)
    Rack::MockRequest.new(app)
  end

  it 'returns ok status payload' do
    response = request.get('/healthz')

    expect(response.status).to eq(200)
    expect(JSON.parse(response.body)).to eq({ 'status' => 'ok', 'service' => 'savant-http' })
  end
end
