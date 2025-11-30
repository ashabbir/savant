#!/usr/bin/env ruby
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/savant/agent/prompt_builder'
require_relative '../../../lib/savant/framework/engine/runtime_context'

RSpec.describe Savant::Agent::PromptBuilder do
  let(:runtime) do
    Savant::RuntimeContext.new(
      session_id: 's1',
      persona: { name: 'test', version: 1, prompt_md: 'Be helpful.' },
      driver_prompt: { version: 'v1', prompt_md: 'Always return JSON.' },
      amr_rules: { rules: [{ 'id' => 'r1', 'priority' => 'high' }] },
      repo: { path: '/tmp/repo', branch: 'main' },
      memory: {},
      logger: nil,
      multiplexer: nil
    )
  end

  it 'builds a deterministic prompt with sections' do
    pb = described_class.new(runtime: runtime)
    prompt = pb.build(goal: 'Do X', memory: { steps: [] })
    expect(prompt).to include('## Persona')
    expect(prompt).to include('## Driver')
    expect(prompt).to include('## Goal')
    expect(prompt).to include('## Action Schema')
  end
end
