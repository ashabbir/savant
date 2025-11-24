#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'rack/mock'

require_relative '../../../lib/savant/http/router'

module McpSseSpec
  class FakeRegistrar
    def specs
      [{ 'name' => 'echo', 'description' => 'echo', 'inputSchema' => { 'type' => 'object' } }]
    end

    def call(name, params, ctx: {})
      { 'echo' => params, 'user' => ctx[:user_id] }
    end
  end

  class FakeServiceManager
    attr_reader :registrar, :service
    def initialize
      @service = 'context'
      @registrar = FakeRegistrar.new
    end

    def service_info
      { name: 'context', version: '1.0.0' }
    end
  end

  def self.build_app
    Savant::HTTP::Router.build(mounts: { 'context' => FakeServiceManager.new }, transport: 'http')
  end
end

RSpec.describe 'MCP SSE streaming' do
  let(:app) { McpSseSpec.build_app }

  it 'streams result events for tools/call' do
    req = Rack::MockRequest.new(app)
    rpc = { jsonrpc: '2.0', id: 9, method: 'tools/call', params: { name: 'echo', arguments: { msg: 'hi' } } }
    res = req.get('/mcp/context/stream?request=' + Rack::Utils.escape(JSON.generate(rpc)), 'HTTP_X_SAVANT_USER_ID' => 'sse')
    expect(res.status).to eq(200)
    expect(res['Content-Type']).to include('text/event-stream')
    # ensure the body contains result and done events
    body = res.body
    expect(body).to include('event: result')
    expect(body).to include('event: done')
  end
end

