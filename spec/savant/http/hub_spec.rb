# frozen_string_literal: true

require 'json'
require 'rack/mock'

require_relative '../../../lib/savant/hub/router'

module HubSpec
  class FakeRegistrar
    def initialize(tools)
      @tools = tools
    end

    def specs
      @tools.map { |t| { 'name' => t } }
    end

    def call(name, params, ctx: {})
      { 'ok' => true, 'tool' => name, 'input' => params, 'user' => ctx[:user_id] }
    end
  end

  class FakeServiceManager
    attr_reader :service, :registrar

    def initialize(service:, tools: ['ping'])
      @service = service
      @registrar = FakeRegistrar.new(tools)
      @start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def service_info
      { name: service, version: '1.0.0' }
    end

    def uptime
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start).to_i
    end
  end

  def self.build_app
    mounts = {
      'context' => FakeServiceManager.new(service: 'context', tools: %w[fts/search fts/stats]),
      'jira' => FakeServiceManager.new(service: 'jira', tools: %w[jira_search jira_self])
    }
    Savant::Hub::Router.build(mounts: mounts, transport: 'sse')
  end
end

RSpec.describe 'Savant HTTP Hub Router' do
  let(:app) { HubSpec.build_app }
  let(:request) { Rack::MockRequest.new(app) }

  it 'serves root hub overview' do
    res = request.get('/', 'HTTP_X_SAVANT_USER_ID' => 'tester')
    expect(res.status).to eq(200)
    body = JSON.parse(res.body)
    expect(body['service']).to eq('Savant MCP Hub')
    expect(body['transport']).to eq('sse')
    expect(body['engines']).to be_a(Array)
    expect(body['engines'].map { |e| e['name'] }).to include('context', 'jira')
  end

  it 'lists tools for a mounted engine' do
    res = request.get('/context/tools', 'HTTP_X_SAVANT_USER_ID' => 'amd')
    expect(res.status).to eq(200)
    body = JSON.parse(res.body)
    expect(body['tools']).to be_a(Array)
    expect(body['tools'].map { |t| t['name'] }).to include('fts/search')
  end

  it 'executes tool via POST /:engine/tools/:name/call' do
    payload = { 'params' => { 'q' => 'hello' } }
    res = request.post('/context/tools/fts/search/call', 'CONTENT_TYPE' => 'application/json',
                                                         'HTTP_X_SAVANT_USER_ID' => 'amd', input: JSON.generate(payload))
    expect(res.status).to eq(200)
    out = JSON.parse(res.body)
    expect(out['ok']).to eq(true)
    expect(out['tool']).to eq('fts/search')
    expect(out['input']).to eq({ 'q' => 'hello' })
    expect(out['user']).to eq('amd')
  end

  it 'returns 404 for unknown engine' do
    res = request.get('/unknown/tools', 'HTTP_X_SAVANT_USER_ID' => 'amd')
    expect(res.status).to eq(404)
  end
end
