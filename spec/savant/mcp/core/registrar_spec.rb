# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../../lib/savant/framework/mcp/core/registrar'
require_relative '../../../../lib/savant/framework/mcp/core/dsl'

RSpec.describe Savant::Framework::MCP::Core::Registrar do
  it 'collects specs and dispatches handlers' do
    reg = Savant::Framework::MCP::Core::DSL.build do
      tool 'ns/echo', description: 'Echo args',
                      schema: { type: 'object', properties: { msg: { type: 'string' } }, required: ['msg'] } do |ctx, args|
        { echoed: args['msg'], rid: ctx[:request_id] }
      end
    end

    specs = reg.specs
    expect(specs.length).to eq(1)
    expect(specs.first[:name]).to eq('ns/echo')
    result = reg.call('ns/echo', { 'msg' => 'hi' }, ctx: { request_id: 'r1' })
    expect(result).to eq({ echoed: 'hi', rid: 'r1' })
  end

  it 'runs middleware around handlers in order' do
    order = []
    reg = Savant::Framework::MCP::Core::DSL.build do
      middleware do |ctx, name, args, nxt|
        order << :before
        out = nxt.call(ctx.merge(mid: true), name, args)
        order << :after
        out
      end
      tool 't/one', description: 'test' do |ctx, _args|
        order << :handler
        { mid: ctx[:mid] }
      end
    end

    res = reg.call('t/one', {}, ctx: {})
    expect(res).to eq({ mid: true })
    expect(order).to eq(%i[before handler after])
  end

  it 'raises Unknown tool on missing name' do
    reg = Savant::Framework::MCP::Core::Registrar.new
    expect { reg.call('missing', {}) }.to raise_error('Unknown tool')
  end
end
