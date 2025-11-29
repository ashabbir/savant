# frozen_string_literal: true

require 'spec_helper'
require 'savant/framework/mcp/core/dsl'
require 'savant/framework/mcp/core/validation_middleware'

RSpec.describe Savant::Framework::MCP::Core::ValidationMiddleware do
  it 'coerces input and validates output when provided' do
    reg = Savant::Framework::MCP::Core::DSL.build do
      middleware do |ctx, nm, a, nxt|
        Savant::Framework::MCP::Core::ValidationMiddleware.new.call(ctx, nm, a, nxt)
      end

      tool 'adder/sum', description: 'sum',
                        schema: { type: 'object', properties: { a: { type: 'integer' }, b: { type: 'integer' } }, required: %w[a b] },
                        output_schema: { type: 'object', properties: { result: { type: 'integer' } }, required: ['result'] } do |_ctx, a|
        { 'result' => Integer(a['a']) + Integer(a['b']) }
      end
    end

    out = reg.call('adder/sum', { 'a' => '2', 'b' => 3 }, ctx: {})
    expect(out).to eq('result' => 5)
  end

  it 'raises validation error on missing required' do
    reg = Savant::Framework::MCP::Core::DSL.build do
      middleware do |ctx, nm, a, nxt|
        Savant::Framework::MCP::Core::ValidationMiddleware.new.call(ctx, nm, a, nxt)
      end

      tool 'echo/need', description: 'needs x',
                        schema: { type: 'object', properties: { x: { type: 'string' } }, required: ['x'] } do |_ctx, a|
        a
      end
    end

    expect { reg.call('echo/need', {}, ctx: {}) }.to raise_error(/validation error: missing required/)
  end
end
