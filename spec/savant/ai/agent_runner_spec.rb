# frozen_string_literal: true

require 'spec_helper'
require 'savant/engines/ai/agent_runner'
require 'savant/framework/mcp/core/dsl'

RSpec.describe Savant::AI::AgentRunner do
  it 'runs a sequential plan and threads memory' do
    reg = Savant::Framework::MCP::Core::DSL.build do
      tool 'a/one' do |_ctx, _a|
        { 'n' => 1 }
      end
      tool 'b/two' do |_ctx, a|
        { 'sum' => 2 + (a['memory'] && a['memory'].dig('a/one', 'n') || 0) }
      end
    end

    invoker = proc { |name, args| reg.call(name, args, ctx: {}) }
    agent = described_class.new(invoker: invoker)
    plan = [
      { tool: 'a/one', args: {} },
      { tool: 'b/two', args: { use_memory: true } }
    ]
    out = agent.run(plan, memory: {})
    expect(out[:results].size).to eq(2)
    expect(out[:memory]['a/one']).to eq('n' => 1)
    expect(out[:results][1][:output]['sum']).to eq(3)
  end
end
