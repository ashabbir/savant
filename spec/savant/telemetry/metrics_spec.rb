# frozen_string_literal: true

require 'spec_helper'

require 'savant/telemetry/metrics'
require 'savant/telemetry/exporter'

RSpec.describe Savant::Telemetry::Metrics do
  before { described_class.reset! }

  it 'tracks counters per label set' do
    described_class.increment('tool_invocations_total', tool: 'fts/search', service: 'context')
    described_class.increment('tool_invocations_total', tool: 'fts/search', service: 'context')
    described_class.increment('tool_invocations_total', tool: 'scope/list', service: 'context')

    snapshot = described_class.snapshot
    entries = snapshot['tool_invocations_total']
    search_entry = entries.find { |e| e[:labels][:tool] == 'fts/search' }
    expect(search_entry[:value]).to eq(2)
    scope_entry = entries.find { |e| e[:labels][:tool] == 'scope/list' }
    expect(scope_entry[:value]).to eq(1)
  end

  it 'observes durations and exports prometheus metrics' do
    described_class.increment('tool_invocations_total', tool: 'fts/search', service: 'context')
    described_class.observe('tool_duration_seconds', 0.15, tool: 'fts/search', service: 'context')
    described_class.observe('tool_duration_seconds', 0.1, tool: 'fts/search', service: 'context')

    snapshot = described_class.snapshot
    samples = snapshot['tool_duration_seconds']
    entry = samples.first
    expect(entry[:count]).to eq(2)
    expect(entry[:sum]).to be_within(0.0001).of(0.25)
    expect(entry[:max]).to be > 0.14

    text = Savant::Telemetry::Exporter.prometheus(snapshot)
    expect(text).to include('tool_invocations_total{service="context",tool="fts/search"} 1')
  end
end
