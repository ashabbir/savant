# frozen_string_literal: true

require 'spec_helper'
require 'savant/framework/sdk/ruby_client'

RSpec.describe Savant::SDK::RubyClient do
  it 'constructs JSON-RPC calls and parses responses using a pluggable transport' do
    seen = []
    transport = proc do |url, body|
      seen << [url, JSON.parse(body)]
      # respond with a static tools list
      { jsonrpc: '2.0', id: seen.last[1]['id'], result: { tools: [{ name: 'x/y', description: 'd', inputSchema: {} }] } }.to_json
    end

    client = described_class.new(url: 'http://example/jsonrpc', &transport)
    res = client.list_tools
    expect(res['result']).to be_a(Hash)
    expect(res['result']['tools'].first['name']).to eq('x/y')
    expect(seen.first[0]).to eq('http://example/jsonrpc')
    expect(seen.first[1]['method']).to eq('tools/list')
  end
end
