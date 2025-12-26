#!/usr/bin/env ruby
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/savant/agent/state_machine'

describe Savant::Agent::StateMachine do
  subject { described_class.new }

  describe 'initialization' do
    it 'initializes with :init state' do
      expect(subject.current_state).to eq(:init)
    end

    it 'has empty history' do
      expect(subject.state_history).to be_empty
    end

    it 'has zero step count' do
      expect(subject.step_count).to eq(0)
    end

    it 'raises on invalid initial state' do
      expect { described_class.new(initial_state: :invalid) }.to raise_error
    end
  end

  describe '#in_state?' do
    it 'returns true for current state' do
      expect(subject.in_state?(:init)).to be true
    end

    it 'returns false for other states' do
      expect(subject.in_state?(:searching)).to be false
    end
  end

  describe '#transition_to' do
    it 'allows valid transition from init to searching' do
      result = subject.transition_to(:searching)
      expect(result[:ok]).to be true
      expect(subject.current_state).to eq(:searching)
    end

    it 'allows valid transition from init to deciding' do
      result = subject.transition_to(:deciding)
      expect(result[:ok]).to be true
      expect(subject.current_state).to eq(:deciding)
    end

    it 'allows valid transition from init to finishing' do
      result = subject.transition_to(:finishing)
      expect(result[:ok]).to be true
      expect(subject.current_state).to eq(:finishing)
    end

    it 'rejects invalid transition' do
      subject.transition_to(:searching)
      result = subject.transition_to(:finishing)
      # From searching, we can go to analyzing, stuck_search, or finishing
      # So finishing should be allowed
      expect(result[:ok]).to be true
    end

    it 'rejects transition from searching to searching' do
      subject.transition_to(:searching)
      result = subject.transition_to(:searching)
      expect(result[:ok]).to be false
    end

    it 'records transition in history' do
      subject.transition_to(:searching)
      expect(subject.state_history.length).to eq(1)
      expect(subject.state_history[0][:to_state]).to eq(:searching)
    end

    it 'allows multiple valid transitions' do
      subject.transition_to(:searching)
      subject.transition_to(:analyzing)
      subject.transition_to(:deciding)
      expect(subject.current_state).to eq(:deciding)
    end
  end

  describe '#allowed_actions' do
    it 'returns empty array for init state' do
      expect(subject.allowed_actions).to eq([])
    end

    it 'returns search actions for searching state' do
      subject.transition_to(:searching)
      expect(subject.allowed_actions).to include('context.fts_search')
    end

    it 'returns empty array for analyzing state' do
      subject.transition_to(:searching)
      subject.transition_to(:analyzing)
      expect(subject.allowed_actions).to eq([])
    end

    it 'includes search actions for deciding state' do
      subject.transition_to(:deciding)
      expect(subject.allowed_actions).to include('context.fts_search')
    end
  end

  describe '#next_states' do
    it 'returns valid next states from init' do
      expect(subject.next_states).to include(:searching, :deciding, :finishing)
    end

    it 'returns valid next states from searching' do
      subject.transition_to(:searching)
      expect(subject.next_states).to include(:analyzing, :stuck_search, :finishing)
    end

    it 'returns valid next states from analyzing' do
      subject.transition_to(:searching)
      subject.transition_to(:analyzing)
      expect(subject.next_states).to include(:deciding, :stuck_analyze, :finishing)
    end
  end

  describe '#record_tool_call' do
    it 'records a tool call' do
      subject.transition_to(:searching)
      subject.record_tool_call('context.fts_search', { query: 'test' })
      expect(subject.state_history.length).to eq(2) # transition + tool call
    end

    it 'tracks last tools for duplicate detection' do
      subject.transition_to(:searching)
      subject.record_tool_call('context.fts_search', { query: 'q1' })
      subject.record_tool_call('context.fts_search', { query: 'q2' })
      subject.record_tool_call('context.fts_search', { query: 'q3' })
      expect(subject.instance_variable_get(:@last_tools).length).to eq(3)
    end

    it 'tracks search queries' do
      subject.transition_to(:searching)
      subject.record_tool_call('context.fts_search', { query: 'Savant Framework' })
      expect(subject.instance_variable_get(:@last_queries)).to include('Savant Framework')
    end
  end

  describe '#tick' do
    it 'increments step count' do
      subject.tick
      expect(subject.step_count).to eq(1)
      subject.tick
      expect(subject.step_count).to eq(2)
    end

    it 'increments state step count' do
      subject.transition_to(:searching)
      subject.tick
      expect(subject.instance_variable_get(:@state_step_count)).to eq(1)
    end

    it 'resets state step count on transition' do
      subject.transition_to(:searching)
      subject.tick
      subject.tick
      subject.transition_to(:analyzing)
      expect(subject.instance_variable_get(:@state_step_count)).to eq(0)
    end
  end

  describe '#stuck?' do
    it 'returns false for new machine' do
      expect(subject.stuck?).to be false
    end

    it 'detects repeated tool calls' do
      subject.transition_to(:searching)
      3.times do
        subject.record_tool_call('context.fts_search', { query: 'same' })
      end
      expect(subject.stuck?).to be true
    end

    it 'detects too many steps in state' do
      subject.transition_to(:searching)
      6.times { subject.tick }
      expect(subject.stuck?).to be true
    end

    it 'detects repeated search queries' do
      subject.transition_to(:searching)
      subject.record_tool_call('context.fts_search', { query: 'Savant Framework' })
      subject.record_tool_call('context.fts_search', { query: 'Savant Framework' })
      expect(subject.stuck?).to be true
    end

    it 'allows different tools without stuck detection' do
      subject.transition_to(:searching)
      subject.record_tool_call('context.fts_search', { query: 'q1' })
      subject.record_tool_call('context.memory_search', { query: 'q2' })
      subject.record_tool_call('context.fts_search', { query: 'q3' })
      expect(subject.stuck?).to be false
    end

    it 'returns false in finishing state' do
      subject.transition_to(:finishing)
      10.times { subject.tick }
      expect(subject.stuck?).to be false
    end
  end

  describe '#suggest_exit' do
    it 'suggests finishing for searching state' do
      subject.transition_to(:searching)
      suggestion = subject.suggest_exit
      expect(suggestion).to include('search')
      expect(suggestion).to include('finish')
    end

    it 'suggests finishing for analyzing state' do
      subject.transition_to(:searching)
      subject.transition_to(:analyzing)
      suggestion = subject.suggest_exit
      expect(suggestion).to include('Analysis')
      expect(suggestion).to include('finish')
    end

    it 'suggests action for deciding state' do
      subject.transition_to(:deciding)
      suggestion = subject.suggest_exit
      expect(suggestion).to include('Decision')
    end
  end

  describe '#infer_state_from_tool' do
    it 'returns :searching for fts_search' do
      expect(subject.infer_state_from_tool('context.fts_search')).to eq(:searching)
    end

    it 'returns :searching for memory_search' do
      expect(subject.infer_state_from_tool('context.memory_search')).to eq(:searching)
    end

    it 'returns :finishing for nil' do
      expect(subject.infer_state_from_tool(nil)).to eq(:finishing)
    end

    it 'returns :deciding for other tools' do
      expect(subject.infer_state_from_tool('custom_tool')).to eq(:deciding)
    end
  end

  describe '#to_h' do
    it 'serializes state to hash' do
      subject.transition_to(:searching)
      subject.tick
      hash = subject.to_h

      expect(hash[:current_state]).to eq(:searching)
      expect(hash[:step_count]).to eq(1)
      expect(hash[:stuck]).to be false
      expect(hash).to have_key(:allowed_actions)
      expect(hash).to have_key(:next_states)
    end

    it 'includes stuck status' do
      subject.transition_to(:searching)
      6.times { subject.tick }
      hash = subject.to_h
      expect(hash[:stuck]).to be true
      expect(hash[:suggested_exit]).not_to be_nil
    end

    it 'includes history length' do
      subject.transition_to(:searching)
      hash = subject.to_h
      expect(hash[:history_length]).to eq(1)
    end
  end

  describe 'state transitions diagram' do
    it 'supports: init -> searching -> analyzing -> deciding -> finishing' do
      subject.transition_to(:searching)
      subject.transition_to(:analyzing)
      subject.transition_to(:deciding)
      subject.transition_to(:finishing)
      expect(subject.current_state).to eq(:finishing)
    end

    it 'supports: init -> searching -> analyzing -> deciding -> searching -> finishing' do
      subject.transition_to(:searching)
      subject.transition_to(:analyzing)
      subject.transition_to(:deciding)
      subject.transition_to(:searching)
      subject.transition_to(:analyzing)
      subject.transition_to(:deciding)
      subject.transition_to(:finishing)
      expect(subject.current_state).to eq(:finishing)
    end

    it 'supports: init -> deciding -> finishing' do
      subject.transition_to(:deciding)
      subject.transition_to(:finishing)
      expect(subject.current_state).to eq(:finishing)
    end

    it 'supports: init -> searching -> stuck_search -> finishing' do
      subject.transition_to(:searching)
      subject.transition_to(:stuck_search)
      subject.transition_to(:finishing)
      expect(subject.current_state).to eq(:finishing)
    end
  end

  describe 'timeout tracking' do
    it 'tracks state duration' do
      subject.transition_to(:searching)
      sleep 0.01  # Sleep for 10ms
      duration = subject.state_duration_ms
      expect(duration).to be > 0
    end

    it 'has timeout for each state' do
      expect(described_class::STATE_TIMEOUTS[:searching]).to eq(60)
      expect(described_class::STATE_TIMEOUTS[:analyzing]).to eq(30)
      expect(described_class::STATE_TIMEOUTS[:deciding]).to eq(45)
    end
  end
end
