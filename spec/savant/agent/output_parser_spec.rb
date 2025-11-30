#!/usr/bin/env ruby
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/savant/agent/output_parser'

RSpec.describe Savant::Agent::OutputParser do
  it 'parses a valid JSON envelope' do
    text = '{"action":"finish","tool_name":"","args":{},"final":"done","reasoning":"ok"}'
    out = described_class.parse(text)
    expect(out['action']).to eq('finish')
    expect(out['final']).to eq('done')
  end

  it 'extracts JSON from fenced code block' do
    text = <<~TXT
      ```json
      {"action":"tool","tool_name":"context.fts.search","args":{"q":"memory"},"final":"","reasoning":"searching"}
      ```
    TXT
    out = described_class.parse(text)
    expect(out['action']).to eq('tool')
    expect(out['tool_name']).to eq('context.fts.search')
    expect(out['args']).to be_a(Hash)
  end

  it 'raises on malformed JSON' do
    expect do
      described_class.parse('not json at all')
    end.to raise_error(StandardError, 'malformed_json')
  end
end

