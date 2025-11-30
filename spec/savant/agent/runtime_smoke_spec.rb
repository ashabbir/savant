#!/usr/bin/env ruby
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/savant/agent/runtime'
require_relative '../../../lib/savant/framework/engine/runtime_context'

RSpec.describe Savant::Agent::Runtime do
  before do
    Savant::Framework::Runtime.current = Savant::RuntimeContext.new(
      session_id: 's1',
      persona: { name: 'test', version: 1, prompt_md: 'Be helpful.' },
      driver_prompt: { version: 'v1', prompt_md: 'Always return JSON.' },
      amr_rules: { rules: [] },
      repo: nil,
      memory: {},
      logger: nil,
      multiplexer: nil
    )
  end

  after do
    Savant::Framework::Runtime.current = nil
  end

  it 'runs a dry-run session to finish' do
    allow(Savant::LLM).to receive(:call).and_return({ text: '{"action":"finish","tool_name":"","args":{},"final":"ok","reasoning":"done"}', usage: { prompt_tokens: 10, output_tokens: 3 } })
    agent = described_class.new(goal: 'Say hello')
    res = agent.run(max_steps: 3, dry_run: true)
    expect(res[:status]).to eq('ok')
    expect(res[:final]).to eq('ok')
  end
end
