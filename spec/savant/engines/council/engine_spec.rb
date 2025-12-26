#!/usr/bin/env ruby
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/savant/version'
require_relative '../../../../lib/savant/engines/council/engine'
require_relative '../../../../lib/savant/engines/council/ops'

RSpec.describe Savant::Council::Engine do
  # Mock Ops class for testing engine delegation
  class MockOps
    attr_reader :calls

    def initialize
      @calls = []
    end

    def session_create(title: nil, agents: [], user_id: nil, description: nil)
      @calls << [:session_create, { title: title, agents: agents, user_id: user_id, description: description }]
      { id: 1, title: title, agents: agents, description: description }
    end

    def sessions_list(limit: 50)
      @calls << [:sessions_list, { limit: limit }]
      []
    end

    def session_get(id:)
      @calls << [:session_get, { id: id }]
      { id: id, title: 'Test', messages: [], mode: 'chat' }
    end

    def session_update(id:, title: nil, agents: nil, description: nil)
      @calls << [:session_update, { id: id, title: title, agents: agents, description: description }]
      { id: id, title: title }
    end

    def session_delete(id:)
      @calls << [:session_delete, { id: id }]
      { ok: true }
    end

    def append_user(session_id:, text:, user_id: nil)
      @calls << [:append_user, { session_id: session_id, text: text, user_id: user_id }]
      { ok: true }
    end

    def append_agent(session_id:, agent_name:, run_id: nil, text: nil, status: 'ok')
      @calls << [:append_agent, { session_id: session_id, agent_name: agent_name, run_id: run_id, text: text, status: status }]
      { ok: true }
    end

    def agent_step(session_id:, goal_text:, agent_name: nil)
      @calls << [:agent_step, { session_id: session_id, goal_text: goal_text, agent_name: agent_name }]
      { status: 'ok' }
    end

    def council_roles
      @calls << [:council_roles, {}]
      [{ id: 'analyst', name: 'Analyst', description: 'Test' }]
    end

    def session_mode(session_id:)
      @calls << [:session_mode, { session_id: session_id }]
      'chat'
    end

    def escalate_to_council(session_id:, query: nil, user_id: nil)
      @calls << [:escalate_to_council, { session_id: session_id, query: query, user_id: user_id }]
      { ok: true, run_id: 'council-1-abc', mode: 'council' }
    end

    def run_council_protocol(session_id:, run_id: nil, max_debate_rounds: 2)
      @calls << [:run_council_protocol, { session_id: session_id, run_id: run_id, max_debate_rounds: max_debate_rounds }]
      { ok: true, status: 'completed' }
    end

    def return_to_chat(session_id:, message: nil)
      @calls << [:return_to_chat, { session_id: session_id, message: message }]
      { ok: true, mode: 'chat' }
    end

    def council_status(session_id:)
      @calls << [:council_status, { session_id: session_id }]
      { session_id: session_id, mode: 'chat', council_run: nil, roles: [] }
    end

    def get_council_run(run_id:)
      @calls << [:get_council_run, { run_id: run_id }]
      { run_id: run_id, status: 'completed' }
    end

    def list_council_runs(session_id:, limit: 20)
      @calls << [:list_council_runs, { session_id: session_id, limit: limit }]
      []
    end
  end

  let(:mock_ops) { MockOps.new }
  let(:engine) do
    eng = described_class.new
    eng.instance_variable_set(:@ops, mock_ops)
    eng
  end

  describe '#server_info' do
    it 'returns engine info' do
      info = engine.server_info
      expect(info[:name]).to eq('council')
      expect(info[:description]).to include('Council')
    end
  end

  describe 'session management' do
    it 'delegates session_create to ops' do
      engine.session_create(title: 'Test', agents: ['a1'], user_id: 'u1', description: 'desc')
      expect(mock_ops.calls.last[0]).to eq(:session_create)
      expect(mock_ops.calls.last[1][:title]).to eq('Test')
    end

    it 'delegates sessions_list to ops' do
      engine.sessions_list(limit: 10)
      expect(mock_ops.calls.last[0]).to eq(:sessions_list)
      expect(mock_ops.calls.last[1][:limit]).to eq(10)
    end

    it 'delegates session_get to ops' do
      engine.session_get(id: 123)
      expect(mock_ops.calls.last[0]).to eq(:session_get)
      expect(mock_ops.calls.last[1][:id]).to eq(123)
    end

    it 'delegates session_update to ops' do
      engine.session_update(id: 1, title: 'New Title')
      expect(mock_ops.calls.last[0]).to eq(:session_update)
    end

    it 'delegates session_delete to ops' do
      engine.session_delete(id: 1)
      expect(mock_ops.calls.last[0]).to eq(:session_delete)
    end
  end

  describe 'chat mode operations' do
    it 'delegates append_user to ops' do
      engine.append_user(session_id: 1, text: 'Hello', user_id: 'u1')
      expect(mock_ops.calls.last[0]).to eq(:append_user)
    end

    it 'delegates append_agent to ops' do
      engine.append_agent(session_id: 1, agent_name: 'a1', text: 'Hi', status: 'ok')
      expect(mock_ops.calls.last[0]).to eq(:append_agent)
    end

    it 'delegates agent_step to ops' do
      engine.agent_step(session_id: 1, goal_text: 'Do something', agent_name: 'a1')
      expect(mock_ops.calls.last[0]).to eq(:agent_step)
    end
  end

  describe 'council protocol operations' do
    it 'delegates council_roles to ops' do
      result = engine.council_roles
      expect(mock_ops.calls.last[0]).to eq(:council_roles)
      expect(result).to be_an(Array)
    end

    it 'delegates session_mode to ops' do
      engine.session_mode(session_id: 1)
      expect(mock_ops.calls.last[0]).to eq(:session_mode)
    end

    it 'delegates escalate_to_council to ops' do
      result = engine.escalate_to_council(session_id: 1, query: 'Test?', user_id: 'u1')
      expect(mock_ops.calls.last[0]).to eq(:escalate_to_council)
      expect(result[:ok]).to be true
    end

    it 'delegates run_council to ops' do
      result = engine.run_council(session_id: 1, max_debate_rounds: 3)
      expect(mock_ops.calls.last[0]).to eq(:run_council_protocol)
      expect(mock_ops.calls.last[1][:max_debate_rounds]).to eq(3)
    end

    it 'delegates return_to_chat to ops' do
      result = engine.return_to_chat(session_id: 1, message: 'Done')
      expect(mock_ops.calls.last[0]).to eq(:return_to_chat)
      expect(result[:mode]).to eq('chat')
    end

    it 'delegates council_status to ops' do
      result = engine.council_status(session_id: 1)
      expect(mock_ops.calls.last[0]).to eq(:council_status)
      expect(result[:session_id]).to eq(1)
    end

    it 'delegates get_council_run to ops' do
      engine.get_council_run(run_id: 'council-1-abc')
      expect(mock_ops.calls.last[0]).to eq(:get_council_run)
    end

    it 'delegates list_council_runs to ops' do
      engine.list_council_runs(session_id: 1, limit: 5)
      expect(mock_ops.calls.last[0]).to eq(:list_council_runs)
      expect(mock_ops.calls.last[1][:limit]).to eq(5)
    end
  end
end
