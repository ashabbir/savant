# frozen_string_literal: true

require 'json'
require 'rack/mock'
require 'tmpdir'

require_relative '../../../lib/savant/http/router'

module LogsSpec
  class FakeRegistrar
    def specs = []
  end

  class FakeServiceManager
    attr_reader :service, :registrar
    def initialize(service:)
      @service = service
      @registrar = FakeRegistrar.new
    end
    def service_info = { name: service, version: '1.0.0' }
  end
end

RSpec.describe 'Logs endpoint' do
  it 'returns last N lines as JSON and can stream via SSE' do
    Dir.mktmpdir do |dir|
      logs_dir = File.join(dir, 'savant')
      Dir.mkdir(logs_dir)
      path = File.join(logs_dir, 'context.log')
      File.write(path, "one\ntwo\n")

      mounts = { 'context' => LogsSpec::FakeServiceManager.new(service: 'context') }
      app = Savant::HTTP::Router.build(mounts: mounts, transport: 'sse', logs_dir: logs_dir)
      req = Rack::MockRequest.new(app)

      res = req.get('/context/logs?n=1', 'HTTP_X_SAVANT_USER_ID' => 'bob')
      expect(res.status).to eq(200)
      data = JSON.parse(res.body)
      expect(data['lines']).to eq(['two'])

      # SSE once: should emit last lines and close
      res2 = req.get('/context/logs?stream=1&n=2&once=1', 'HTTP_X_SAVANT_USER_ID' => 'bob')
      expect(res2.status).to eq(200)
      expect(res2['Content-Type']).to eq('text/event-stream')
      body = res2.body.to_s
      expect(body).to include('event: log')
      expect(body).to include('data: {"line":"one"}')
      expect(body).to include('data: {"line":"two"}')
    end
  end
end
