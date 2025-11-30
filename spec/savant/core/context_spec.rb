# frozen_string_literal: true

require 'spec_helper'
require 'savant/framework/engine/context'

RSpec.describe Savant::Framework::Engine::Context do
  it 'exposes logger and config with sensible defaults' do
    ctx = described_class.new
    expect(ctx.logger).to be_a(Savant::Logging::Logger)
    expect(ctx.config).to be_a(Hash)
  end

  it 'allows overriding logger/config/db and does not require DB by default' do
    fake_logger = Savant::Logging::Logger.new(io: $stdout, json: true, service: 'test')
    cfg = { 'env' => 'test' }
    ctx = described_class.new(logger: fake_logger, config: cfg)
    expect(ctx.logger).to eq(fake_logger)
    expect(ctx.config).to eq(cfg)
    expect(ctx.db).to be_nil
  end

  it 'falls back to existing JSON settings when YAML is absent' do
    ctx = described_class.new
    expect(ctx.config).to include('indexer', 'database')
  end
end
