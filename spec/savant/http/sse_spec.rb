# frozen_string_literal: true

require 'rack/mock'

require_relative '../../../lib/savant/http/sse'

RSpec.describe Savant::HTTP::SSE do
  it 'sets correct SSE headers and yields at least one event when once=1' do
    app = described_class.new(heartbeat_interval: 0.01)
    env = Rack::MockRequest.env_for('/stream?once=1', 'REQUEST_METHOD' => 'GET')
    status, headers, body = app.call(env)

    expect(status).to eq(200)
    expect(headers['Content-Type']).to eq('text/event-stream')
    expect(headers['Cache-Control']).to include('no-cache')
    chunks = []
    body.each { |c| chunks << c }
    body.close if body.respond_to?(:close)

    expect(chunks.join).to include('event: heartbeat')
    expect(chunks.join).to include('data: {}')
  end
end
