#!/usr/bin/env ruby
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/savant/version'
require_relative '../../../../lib/savant/engines/council/tools'
require_relative '../../../../lib/savant/engines/council/engine'

RSpec.describe Savant::Council::Tools do
  # Mock Engine for testing tools registration
  class MockEngine
    attr_reader :calls

    def initialize
      @calls = []
    end

    def session_create(title: nil, description: nil, agents: [], user_id: nil)
      @calls << [:session_create, { title: title, description: description, agents: agents, user_id: user_id }]
      { id: 1, title: title, description: description, agents: agents }
    end

    def sessions_list(limit: 50)
      @calls << [:sessions_list, { limit: limit }]
      [{ id: 1, title: 'Test' }]
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

    def council_status(session_id:)
      @calls << [:council_status, { session_id: session_id }]
      { session_id: session_id, mode: 'chat' }
    end

    def escalate_to_council(session_id:, query: nil, user_id: nil)
      @calls << [:escalate_to_council, { session_id: session_id, query: query, user_id: user_id }]
      { ok: true, run_id: 'council-1-abc', mode: 'council' }
    end

    def run_council(session_id:, run_id: nil, max_debate_rounds: 2)
      @calls << [:run_council, { session_id: session_id, run_id: run_id, max_debate_rounds: max_debate_rounds }]
      { ok: true, status: 'completed' }
    end

    def return_to_chat(session_id:, message: nil)
      @calls << [:return_to_chat, { session_id: session_id, message: message }]
      { ok: true, mode: 'chat' }
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

  let(:mock_engine) { MockEngine.new }
  let(:registrar) { described_class.build_registrar(mock_engine) }

  # Get tools via specs method (registrar returns Tool specs via specs method)
  def tools
    registrar.specs
  end

  describe '.build_registrar' do
    it 'returns a registrar with specs' do
      expect(registrar).to respond_to(:specs)
      expect(tools).to be_an(Array)
    end

    it 'registers session management tools' do
      tool_names = tools.map { |t| t[:name] }
      expect(tool_names).to include('council_session_create')
      expect(tool_names).to include('council_sessions_list')
      expect(tool_names).to include('council_session_get')
      expect(tool_names).to include('council_session_update')
      expect(tool_names).to include('council_session_delete')
    end

    it 'registers chat mode tools' do
      tool_names = tools.map { |t| t[:name] }
      expect(tool_names).to include('council_append_user')
      expect(tool_names).to include('council_append_agent')
      expect(tool_names).to include('council_agent_step')
    end

    it 'registers council protocol tools' do
      tool_names = tools.map { |t| t[:name] }
      expect(tool_names).to include('council_roles')
      expect(tool_names).to include('council_status')
      expect(tool_names).to include('council_escalate')
      expect(tool_names).to include('council_run')
      expect(tool_names).to include('council_return_to_chat')
      expect(tool_names).to include('council_run_get')
      expect(tool_names).to include('council_runs_list')
    end
  end

  describe 'tool schemas' do
    it 'council_escalate has required session_id' do
      tool = tools.find { |t| t[:name] == 'council_escalate' }
      expect(tool[:inputSchema][:required]).to include('session_id')
    end

    it 'council_run has required session_id' do
      tool = tools.find { |t| t[:name] == 'council_run' }
      expect(tool[:inputSchema][:required]).to include('session_id')
    end

    it 'council_status has required session_id' do
      tool = tools.find { |t| t[:name] == 'council_status' }
      expect(tool[:inputSchema][:required]).to include('session_id')
    end

    it 'council_run_get has required run_id' do
      tool = tools.find { |t| t[:name] == 'council_run_get' }
      expect(tool[:inputSchema][:required]).to include('run_id')
    end
  end

  describe 'tool descriptions' do
    it 'council_escalate describes escalation' do
      tool = tools.find { |t| t[:name] == 'council_escalate' }
      expect(tool[:description]).to include('Escalate')
    end

    it 'council_run describes protocol execution' do
      tool = tools.find { |t| t[:name] == 'council_run' }
      expect(tool[:description]).to include('protocol')
    end

    it 'council_roles describes available roles' do
      tool = tools.find { |t| t[:name] == 'council_roles' }
      expect(tool[:description]).to include('roles')
    end
  end
end
