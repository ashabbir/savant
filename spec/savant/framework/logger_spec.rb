# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Savant::Logger do
  let(:io) { StringIO.new }
  let(:logger) { described_class.new(io: io, level: :info, json: true, service: 'test', tool: 'unit') }

  it 'emits structured JSON with context fields' do
    logger.info(event: 'tool_call', data: { x: 1 }, request_id: 'req-1')
    io.rewind
    line = io.read
    payload = JSON.parse(line)
    expect(payload['level']).to eq('info')
    expect(payload['service']).to eq('test')
    expect(payload['tool']).to eq('unit')
    expect(payload['event']).to eq('tool_call')
    expect(payload['data']).to eq({ 'x' => 1 })
    expect(payload['request_id']).to eq('req-1')
    expect(payload).to have_key('timestamp')
  end

  it 'supports trace level and duration fields' do
    logger.trace(event: 'tool_end', duration_ms: 12, status: 'ok')
    io.rewind
    line = io.read
    expect(line).not_to eq("")
    payload = JSON.parse(line)
    expect(payload['level']).to eq('trace')
    expect(payload['duration_ms']).to eq(12)
    expect(payload['status']).to eq('ok')
  end
end
