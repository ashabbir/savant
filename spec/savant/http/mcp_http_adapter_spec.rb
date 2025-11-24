#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'rack/mock'

require_relative '../../../lib/savant/http/router'

module HubMcpSpec
  class FakeRegistrar
    def initialize(tools)
      @tools = tools
    end

    def specs
      @tools.map { |t| { 'name' => t, 'description' => 'test', 'inputSchema' => {} } }
    end

    def call(name, params, ctx: {})
      { 'ok' => true, 'tool' => name, 'args' => params, 'user' => ctx[:user_id] }
    end
  end

  class FakeServiceManager
    attr_reader :service, :registrar

    def initialize(service:, tools: ['ping'])
      @service = service
      @registrar = FakeRegistrar.new(tools)
    end

    def service_info
      { name: service, version: '1.0.0', description: "svc=#{service}" }
    end

    def specs
      @registrar.specs
    end
  end

  def self.build_app
    mounts = {
      'context' => FakeServiceManager.new(service: 'context', tools: %w[fts/search fts/stats])
    }
    Savant::HTTP::Router.build(mounts: mounts, transport: 'http')
  end
end

RSpec.describe 'Hub MCP HTTP adapter' do
  let(:app) { HubMcpSpec.build_app }
  let(:request) { Rack::MockRequest.new(app) }

  it 'handles initialize over /mcp/:engine' do
    payload = { jsonrpc: '2.0', id: 1, method: 'initialize', params: {} }
    res = request.post('/mcp/context', 'CONTENT_TYPE' => 'application/json', 'HTTP_X_SAVANT_USER_ID' => 'tester', input: JSON.generate(payload))
    expect(res.status).to eq(200)
    body = JSON.parse(res.body)
    expect(body['result']).to be_a(Hash)
    expect(body['result']['serverInfo']).to be_a(Hash)
    expect(body['result']['protocolVersion']).to be_a(String)
  end

  it 'lists tools via tools/list' do
    payload = { jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} }
    res = request.post('/mcp/context', 'CONTENT_TYPE' => 'application/json', 'HTTP_X_SAVANT_USER_ID' => 't', input: JSON.generate(payload))
    expect(res.status).to eq(200)
    body = JSON.parse(res.body)
    tools = body['result']['tools']
    expect(tools.map { |t| t['name'] }).to include('fts/search', 'fts/stats')
  end

  it 'invokes tools via tools/call and echoes content text' do
    payload = { jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'fts/search', arguments: { q: 'hi' } } }
    res = request.post('/mcp/context', 'CONTENT_TYPE' => 'application/json', 'HTTP_X_SAVANT_USER_ID' => 'amd', input: JSON.generate(payload))
    expect(res.status).to eq(200)
    body = JSON.parse(res.body)
    expect(body['result']).to have_key('content')
    text = body['result']['content'][0]['text']
    expect(text).to include('fts/search')
    expect(text).to include('"q": "hi"')
  end

  it 'supports alternate path /:engine/mcp' do
    payload = { jsonrpc: '2.0', id: 4, method: 'ping' }
    res = request.post('/context/mcp', 'CONTENT_TYPE' => 'application/json', 'HTTP_X_SAVANT_USER_ID' => 'amd', input: JSON.generate(payload))
    expect(res.status).to eq(200)
    body = JSON.parse(res.body)
    expect(body['result']).to eq({ 'ok' => true })
  end
end
