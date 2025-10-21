# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../../lib/savant/mcp/core/validation'

RSpec.describe Savant::MCP::Core::Validation do
  it 'validates required fields and types' do
    schema = { type: 'object', properties: { q: { type: 'string' }, limit: { type: 'integer' } }, required: ['q'] }
    args = { 'q' => 'hello', 'limit' => '5' }
    out = described_class.validate!(schema, args)
    expect(out['q']).to eq('hello')
    expect(out['limit']).to eq(5)
  end

  it 'supports anyOf for string|array|null' do
    schema = { type: 'object',
               properties: { repo: { anyOf: [{ type: 'string' }, { type: 'array', items: { type: 'string' } },
                                             { type: 'null' }] } } }
    expect(described_class.validate!(schema, { 'repo' => 'one' })['repo']).to eq('one')
    expect(described_class.validate!(schema, { 'repo' => %w[a b] })['repo']).to eq(%w[a b])
    expect(described_class.validate!(schema, { 'repo' => nil })['repo']).to eq(nil)
  end

  it 'raises on invalid integer' do
    schema = { type: 'object', properties: { limit: { type: 'integer' } } }
    expect { described_class.validate!(schema, { 'limit' => 'nope' }) }.to raise_error(Savant::MCP::Core::ValidationError)
  end
end
