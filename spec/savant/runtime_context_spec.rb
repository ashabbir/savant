#!/usr/bin/env ruby
# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/savant/framework/engine/runtime_context'

RSpec.describe Savant::RuntimeContext do
  describe 'structure' do
    it 'creates a RuntimeContext with keyword arguments' do
      context = described_class.new(
        session_id: 'test-session',
        persona: { name: 'test-persona' },
        driver_prompt: { version: 'v1' },
        amr_rules: { rules: [] },
        repo: { path: '/test' },
        memory: { ephemeral: {} },
        logger: double('Logger'),
        multiplexer: nil
      )

      expect(context.session_id).to eq('test-session')
      expect(context.persona).to eq({ name: 'test-persona' })
      expect(context.driver_prompt).to eq({ version: 'v1' })
      expect(context.amr_rules).to eq({ rules: [] })
      expect(context.repo).to eq({ path: '/test' })
      expect(context.memory).to eq({ ephemeral: {} })
      expect(context.logger).not_to be_nil
      expect(context.multiplexer).to be_nil
    end

    it 'allows nil values for optional fields' do
      context = described_class.new(
        session_id: 'test',
        persona: nil,
        driver_prompt: nil,
        amr_rules: nil,
        repo: nil,
        memory: nil,
        logger: nil,
        multiplexer: nil
      )

      expect(context.session_id).to eq('test')
      expect(context.persona).to be_nil
    end
  end

  describe '#to_h' do
    it 'returns a hash representation of the runtime context' do
      logger = double('Logger')
      rule1 = { id: 'rule1' }
      rule2 = { id: 'rule2' }
      rule3 = { id: 'rule3' }
      context = described_class.new(
        session_id: 'test-session',
        persona: { name: 'savant-engineer', version: 1 },
        driver_prompt: { version: 'v1', hash: 'abc123' },
        amr_rules: { rules: [rule1, rule2, rule3] },
        repo: { path: '/test/repo' },
        memory: { ephemeral: {} },
        logger: logger,
        multiplexer: nil
      )

      hash = context.to_h

      expect(hash[:session_id]).to eq('test-session')
      expect(hash[:persona]).to eq({ name: 'savant-engineer', version: 1 })
      expect(hash[:driver_prompt]).to eq('v1')
      expect(hash[:amr_rules]).to eq('3 rules')
      expect(hash[:repo]).to eq('/test/repo')
      expect(hash[:memory]).to eq('initialized')
    end

    it 'handles nil values gracefully' do
      context = described_class.new(
        session_id: 'test',
        persona: nil,
        driver_prompt: nil,
        amr_rules: nil,
        repo: nil,
        memory: nil,
        logger: nil,
        multiplexer: nil
      )

      hash = context.to_h

      expect(hash[:session_id]).to eq('test')
      expect(hash[:persona]).to be_nil
      expect(hash[:driver_prompt]).to be_nil
      expect(hash[:amr_rules]).to be_nil
      expect(hash[:repo]).to be_nil
      expect(hash[:memory]).to be_nil
    end
  end
end

RSpec.describe Savant::Framework::Runtime do
  describe '.current' do
    it 'allows setting and getting the current runtime context' do
      context = Savant::RuntimeContext.new(
        session_id: 'test',
        persona: nil,
        driver_prompt: nil,
        amr_rules: nil,
        repo: nil,
        memory: nil,
        logger: nil,
        multiplexer: nil
      )

      described_class.current = context
      expect(described_class.current).to eq(context)
      expect(described_class.current.session_id).to eq('test')
    end

    it 'starts as nil' do
      # Reset to nil
      described_class.current = nil
      expect(described_class.current).to be_nil
    end
  end
end
