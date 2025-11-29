# frozen_string_literal: true

require 'json'
require_relative '../../../lib/savant/mcp_dispatcher'
require_relative '../../../lib/savant/logging/logger'

RSpec.describe Savant::Framework::MCP::Dispatcher do
  let(:log) { Savant::Logging::Logger.new(io: StringIO.new, json: true, service: 'test') }
  let(:dispatcher) { described_class.new(service: 'context', log: log) }

  it 'returns parse error for invalid JSON' do
    _req, err = dispatcher.parse('{')
    expect(err).to be_a(String)
    obj = JSON.parse(err)
    expect(obj['error']).to be_a(Hash)
    expect(obj['error']['code']).to eq(-32_700)
  end

  it 'handles initialize request and returns jsonrpc 2.0 response' do
    req = { 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'initialize' }
    res = dispatcher.handle(req)
    obj = JSON.parse(res)
    expect(obj).to include('jsonrpc' => '2.0', 'id' => 1)
    expect(obj['result']).to be_a(Hash)
    expect(obj['result']).to include('serverInfo')
  end
end
