# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'fileutils'

require 'savant/framework/middleware/trace'
require 'savant/logging/metrics'
require 'savant/logging/audit/policy'
require 'savant/logging/audit/store'

RSpec.describe Savant::Framework::Middleware::Trace do
  let(:io) { StringIO.new }
  let(:logger) { Savant::Logging::Logger.new(io: io, level: :trace, json: true, service: 'context') }
  let(:audit_dir) { Dir.mktmpdir }
  let(:audit_path) { File.join(audit_dir, 'audit.json') }
  let(:policy) do
    Savant::Logging::Audit::Policy.new('sandbox' => false,
                                       'audit' => { 'enabled' => true, 'store' => audit_path },
                                       'replay' => { 'limit' => 2 })
  end
  let(:store) { Savant::Logging::Audit::Store.new(policy.audit_store_path) }

  after do
    FileUtils.rm_f(audit_path)
    FileUtils.remove_dir(audit_dir) if Dir.exist?(audit_dir)
    Savant::Logging::Metrics.reset!
  end

  it 'assigns trace IDs, records audit entries, and updates metrics' do
    middleware = described_class.new(logger_factory: ->(ctx) { ctx[:logger] || logger },
                                     metrics: Savant::Logging::Metrics,
                                     audit_store: store,
                                     policy: policy)

    ctx = { service: 'context' }
    result = middleware.call(ctx, 'context/search', { 'q' => 'foo' }) do |_c, _t, _p|
      { ok: true }
    end

    expect(result).to eq(ok: true)
    expect(ctx[:trace_id]).to be_a(String)

    snapshot = Savant::Logging::Metrics.snapshot
    counter = snapshot['tool_invocations_total'].find { |entry| entry[:labels][:tool] == 'context/search' }
    expect(counter[:value]).to eq(1)

    log_lines = File.readlines(audit_path).map { |line| JSON.parse(line) }
    expect(log_lines.last['trace_id']).to eq(ctx[:trace_id])
    expect(log_lines.last['status']).to eq('success')
  end

  it 'records errors and increments error metrics' do
    middleware = described_class.new(logger_factory: ->(_ctx) { logger },
                                     metrics: Savant::Logging::Metrics,
                                     audit_store: store,
                                     policy: policy)

    expect do
      middleware.call({ service: 'context' }, 'context/search', {}) do
        raise 'boom'
      end
    end.to raise_error(RuntimeError)

    snapshot = Savant::Logging::Metrics.snapshot
    counter = snapshot['tool_errors_total'].find { |entry| entry[:labels][:tool] == 'context/search' }
    expect(counter[:value]).to eq(1)
  end

  it 'raises when sandbox policy forbids system operations' do
    sandbox_policy = Savant::Logging::Audit::Policy.new('sandbox' => true)
    middleware = described_class.new(logger_factory: ->(_ctx) { logger },
                                     metrics: Savant::Logging::Metrics,
                                     audit_store: nil,
                                     policy: sandbox_policy)

    expect do
      middleware.call({ service: 'context', requires_system: true }, 'fs/run', {}) { 'ok' }
    end.to raise_error(Savant::Logging::Audit::Policy::SandboxViolation)
  end
end
