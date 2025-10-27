# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Savant::Middleware::Logging do
  let(:io) { StringIO.new }
  let(:logger) { Savant::Logger.new(io: io, json: true, service: 'test') }
  let(:app) do
    ->(_ctx, _tool, _payload) { { ok: true } }
  end

  it 'logs start and end with duration' do
    mw = described_class.new(app, logger: logger)
    ctx = { service: 'svc', request_id: 'r1' }
    mw.call(ctx, 'tool/demo', {})
    io.flush if io.respond_to?(:flush)
    io.rewind
    lines = io.read.split("\n").map { |l| JSON.parse(l)['event'] }
    expect(lines).to include('tool_start')
    expect(lines).to include('tool_end')
  end

  it 'logs exceptions with error level' do
    bad = ->(_ctx, _tool, _payload) { raise 'boom' }
    mw = described_class.new(bad, logger: logger)
    ctx = { service: 'svc', request_id: 'r2' }
    expect { mw.call(ctx, 'tool/demo', {}) }.to raise_error(StandardError)
    io.rewind
    payloads = io.read.split("\n").map { |l| JSON.parse(l) }
    expect(payloads.any? { |p| p['event'] == 'exception' && p['level'] == 'error' }).to be true
  end
end
