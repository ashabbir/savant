# frozen_string_literal: true

require 'spec_helper'
require 'savant/mcp/core/dsl'
require 'savant/mcp/core/registrar'

RSpec.describe 'Tool composition via ctx.invoke' do
  it 'allows a tool to invoke another tool through the same middleware chain' do
    logs = []

    registrar = Savant::MCP::Core::DSL.build do
      # simple logging middleware to capture execution order
      middleware do |ctx, nm, a, nxt|
        logs << "mw:#{nm}:before"
        out = nxt.call(ctx, nm, a)
        logs << "mw:#{nm}:after"
        out
      end

      tool 'base/echo', description: 'echo', schema: { type: 'object', properties: { msg: { type: 'string' } } } do |_ctx, a|
        { 'echo' => a['msg'] }
      end

      tool 'comp/relay', description: 'relay', schema: { type: 'object', properties: { msg: { type: 'string' } } } do |ctx, a|
        # the relay tool calls echo via ctx.invoke
        ctx.invoke('base/echo', { 'msg' => a['msg'] })
      end
    end

    # enrich ctx with invoke, simulating dispatcher behavior
    ctx = { service: 'test', request_id: '1' }
    invoker = proc { |name, args| registrar.call(name, args, ctx: ctx) }
    # expose both proc and method
    ctx[:invoke] = invoker
    ctx.define_singleton_method(:invoke) { |name, args| invoker.call(name, args) }

    out = registrar.call('comp/relay', { 'msg' => 'hi' }, ctx: ctx)
    expect(out).to eq({ 'echo' => 'hi' })
    # middleware should have wrapped both outer and inner tool calls
    expect(logs).to eq(['mw:comp/relay:before', 'mw:base/echo:before', 'mw:base/echo:after', 'mw:comp/relay:after'])
  end
end
