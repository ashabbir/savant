#!/usr/bin/env ruby
# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative '../../../../lib/savant/engines/council/ops'

RSpec.describe Savant::Council::Ops do
  # Fake DB class that mimics the real DB interface for testing
  class FakeDB
    attr_reader :sessions, :messages, :runs

    def initialize
      @sessions = []
      @messages = []
      @runs = []
      @seq = 0
      @council_schema_initialized = true
    end

    def exec(sql)
      # Handle schema creation statements
      FakeRes.new([])
    end

    def exec_params(sql, params)
      case sql
      when /INSERT INTO council_sessions/
        @seq += 1
        session = {
          id: @seq,
          title: params[0],
          user_id: params[1],
          agents: params[2],
          description: params[3],
          mode: 'chat',
          context: nil,
          artifacts: nil,
          created_at: Time.now.utc.iso8601,
          updated_at: Time.now.utc.iso8601
        }
        @sessions << session
        FakeRes.new([{ 'id' => @seq.to_s }])

      when /SELECT \* FROM council_sessions WHERE id=/
        id = params[0].to_i
        row = @sessions.find { |s| s[:id] == id }
        FakeRes.new(row ? [stringify(row)] : [])

      when /SELECT \* FROM council_sessions ORDER BY id DESC/
        limit = params[0].to_i
        rows = @sessions.last(limit).reverse
        FakeRes.new(rows.map { |r| stringify(r) })

      when /SELECT \* FROM council_messages WHERE session_id=/
        sid = params[0].to_i
        rows = @messages.select { |m| m[:session_id] == sid }.sort_by { |m| m[:id] }
        FakeRes.new(rows.map { |r| stringify(r) })

      when /INSERT INTO council_messages/
        @seq += 1
        @messages << {
          id: @seq,
          session_id: params[0].to_i,
          role: params[1],
          agent_name: params[2],
          run_id: params[3],
          status: params[4],
          text: params[5],
          created_at: Time.now.utc.iso8601
        }
        FakeRes.new([{ 'id' => @seq.to_s }])

      when /SELECT role, agent_name, text, created_at FROM council_messages WHERE session_id=/
        sid = params[0].to_i
        rows = @messages.select { |m| m[:session_id] == sid }.sort_by { |m| m[:id] }.last(1)
        FakeRes.new(rows.map { |r| stringify(r) })

      when /DELETE FROM council_sessions WHERE id=/
        id = params[0].to_i
        @sessions.reject! { |s| s[:id] == id }
        @messages.reject! { |m| m[:session_id] == id }
        @runs.reject! { |r| r[:session_id] == id }
        FakeRes.new([])

      when /UPDATE council_sessions SET title=/
        title = params[0]
        id = params[1].to_i
        sess = @sessions.find { |s| s[:id] == id }
        sess[:title] = title if sess && title
        sess[:updated_at] = Time.now.utc.iso8601 if sess
        FakeRes.new([])

      when /UPDATE council_sessions SET agents=/
        agents = params[0]
        id = params[1].to_i
        sess = @sessions.find { |s| s[:id] == id }
        sess[:agents] = agents if sess
        sess[:updated_at] = Time.now.utc.iso8601 if sess
        FakeRes.new([])

      when /UPDATE council_sessions SET description=/
        desc = params[0]
        id = params[1].to_i
        sess = @sessions.find { |s| s[:id] == id }
        sess[:description] = desc if sess
        sess[:updated_at] = Time.now.utc.iso8601 if sess
        FakeRes.new([])

      when /UPDATE council_sessions SET mode=/
        mode = params[0]
        id = params[1].to_i
        sess = @sessions.find { |s| s[:id] == id }
        sess[:mode] = mode if sess
        sess[:updated_at] = Time.now.utc.iso8601 if sess
        FakeRes.new([])

      when /SELECT mode FROM council_sessions WHERE id=/
        id = params[0].to_i
        sess = @sessions.find { |s| s[:id] == id }
        FakeRes.new(sess ? [{ 'mode' => sess[:mode] || 'chat' }] : [])

      when /INSERT INTO council_runs/
        @seq += 1
        run = {
          id: @seq,
          session_id: params[0].to_i,
          run_id: params[1],
          status: params[2],
          phase: params[3],
          query: params[4],
          context: params[5],
          positions: nil,
          debate_rounds: nil,
          synthesis: nil,
          votes: nil,
          veto: false,
          veto_reason: nil,
          started_at: Time.now.utc.iso8601,
          completed_at: nil,
          error: nil
        }
        @runs << run
        FakeRes.new([{ 'id' => @seq.to_s }])

      when /SELECT \* FROM council_runs WHERE session_id=.* ORDER BY id DESC LIMIT 1/
        sid = params[0].to_i
        run = @runs.select { |r| r[:session_id] == sid }.max_by { |r| r[:id] }
        FakeRes.new(run ? [stringify(run)] : [])

      when /SELECT \* FROM council_runs WHERE run_id=/
        rid = params[0].to_s
        run = @runs.find { |r| r[:run_id] == rid }
        FakeRes.new(run ? [stringify(run)] : [])

      when /SELECT \* FROM council_runs WHERE session_id=.* ORDER BY id DESC LIMIT/
        sid = params[0].to_i
        limit = params[1].to_i
        rows = @runs.select { |r| r[:session_id] == sid }.sort_by { |r| -r[:id] }.first(limit)
        FakeRes.new(rows.map { |r| stringify(r) })

      when /UPDATE council_runs SET status=.*, phase=/
        status = params[0]
        phase = params[1]
        rid = params[2]
        run = @runs.find { |r| r[:run_id] == rid }
        if run
          run[:status] = status
          run[:phase] = phase
          run[:completed_at] = Time.now.utc.iso8601 if status == 'completed'
        end
        FakeRes.new([])

      when /UPDATE council_runs SET positions=/
        positions = params[0]
        rid = params[1]
        run = @runs.find { |r| r[:run_id] == rid }
        run[:positions] = positions if run
        FakeRes.new([])

      when /UPDATE council_runs SET debate_rounds=/
        debate = params[0]
        rid = params[1]
        run = @runs.find { |r| r[:run_id] == rid }
        run[:debate_rounds] = debate if run
        FakeRes.new([])

      when /UPDATE council_runs SET synthesis=/
        synthesis = params[0]
        rid = params[1]
        run = @runs.find { |r| r[:run_id] == rid }
        run[:synthesis] = synthesis if run
        FakeRes.new([])

      when /UPDATE council_runs SET veto=/
        veto = params[0]
        reason = params[1]
        rid = params[2]
        run = @runs.find { |r| r[:run_id] == rid }
        if run
          run[:veto] = veto
          run[:veto_reason] = reason
        end
        FakeRes.new([])

      when /UPDATE council_runs SET status=.*, error=/
        status = params[0]
        error = params[1]
        rid = params[2]
        run = @runs.find { |r| r[:run_id] == rid }
        if run
          run[:status] = status
          run[:error] = error
          run[:completed_at] = Time.now.utc.iso8601
        end
        FakeRes.new([])

      else
        FakeRes.new([])
      end
    end

    # Council-specific helpers
    def ensure_council_schema!
      @council_schema_initialized = true
    end

    def create_council_session(title: nil, user_id: nil, agents: [], description: nil)
      @seq += 1
      session = {
        id: @seq,
        title: title,
        user_id: user_id,
        agents: "{#{agents.join(',')}}",
        description: description,
        mode: 'chat',
        context: nil,
        artifacts: nil,
        created_at: Time.now.utc.iso8601,
        updated_at: Time.now.utc.iso8601
      }
      @sessions << session
      @seq
    end

    def list_council_sessions(limit: 50)
      @sessions.last(limit).reverse.map { |s| stringify(s) }
    end

    def get_council_session(id)
      sess = @sessions.find { |s| s[:id] == id.to_i }
      return nil unless sess
      msgs = @messages.select { |m| m[:session_id] == id.to_i }.sort_by { |m| m[:id] }
      { session: stringify(sess), messages: msgs.map { |m| stringify(m) } }
    end

    def add_council_message(session_id:, role:, agent_name: nil, run_id: nil, text:, status: nil)
      @seq += 1
      @messages << {
        id: @seq,
        session_id: session_id.to_i,
        role: role,
        agent_name: agent_name,
        run_id: run_id,
        status: status,
        text: text,
        created_at: Time.now.utc.iso8601
      }
      true
    end

    def update_council_session(id:, title: nil, agents: nil)
      sess = @sessions.find { |s| s[:id] == id.to_i }
      return false unless sess
      sess[:title] = title if title
      sess[:agents] = "{#{agents.join(',')}}" if agents
      sess[:updated_at] = Time.now.utc.iso8601
      true
    end

    def update_council_description(id:, description: nil)
      sess = @sessions.find { |s| s[:id] == id.to_i }
      return false unless sess
      sess[:description] = description if description
      sess[:updated_at] = Time.now.utc.iso8601
      true
    end

    class FakeRes
      def initialize(rows)
        @rows = rows
      end

      def [](idx)
        @rows[idx]
      end

      def ntuples
        @rows.length
      end

      def to_a
        @rows
      end
    end

    private

    def stringify(h)
      h.transform_values do |v|
        case v
        when Array then "{#{v.join(',')}}"
        when TrueClass then 't'
        when FalseClass then 'f'
        when nil then nil
        else v.to_s
        end
      end.transform_keys(&:to_s)
    end
  end

  let(:db) { FakeDB.new }
  let(:ops) { described_class.new(db: db) }

  describe '#council_roles' do
    it 'returns all defined council roles' do
      roles = ops.council_roles
      expect(roles).to be_an(Array)
      expect(roles.length).to eq(5)
      role_ids = roles.map { |r| r[:id] }
      expect(role_ids).to include('analyst', 'skeptic', 'pragmatist', 'safety', 'moderator')
    end

    it 'includes name and description for each role' do
      roles = ops.council_roles
      analyst = roles.find { |r| r[:id] == 'analyst' }
      expect(analyst[:name]).to eq('Analyst')
      expect(analyst[:description]).to include('Decomposes')
    end
  end

  describe '#session_create' do
    it 'creates a new council session' do
      result = ops.session_create(title: 'Test Council', agents: ['agent1', 'agent2'], user_id: 'user1')
      expect(result[:id]).to be > 0
      expect(result[:title]).to eq('Test Council')
      expect(result[:agents]).to eq(['agent1', 'agent2'])
    end

    it 'creates session with description' do
      result = ops.session_create(title: 'Test', agents: [], description: 'A test description')
      expect(result[:description]).to eq('A test description')
    end
  end

  describe '#sessions_list' do
    before do
      ops.session_create(title: 'Session 1', agents: ['a1'])
      ops.session_create(title: 'Session 2', agents: ['a2'])
      ops.session_create(title: 'Session 3', agents: ['a3'])
    end

    it 'lists all sessions' do
      list = ops.sessions_list(limit: 50)
      expect(list.length).to eq(3)
    end

    it 'respects limit parameter' do
      list = ops.sessions_list(limit: 2)
      expect(list.length).to eq(2)
    end
  end

  describe '#session_get' do
    it 'retrieves a session with messages' do
      created = ops.session_create(title: 'Get Test', agents: ['agent1'])
      ops.append_user(session_id: created[:id], text: 'Hello!')
      ops.append_agent(session_id: created[:id], agent_name: 'agent1', text: 'Hi there!', status: 'ok')

      session = ops.session_get(id: created[:id])
      expect(session[:title]).to eq('Get Test')
      expect(session[:messages].length).to eq(2)
      expect(session[:mode]).to eq('chat')
    end

    it 'raises for non-existent session' do
      expect { ops.session_get(id: 99999) }.to raise_error('not_found')
    end
  end

  describe '#append_user and #append_agent' do
    let(:session) { ops.session_create(title: 'Message Test', agents: ['a1']) }

    it 'appends user messages' do
      result = ops.append_user(session_id: session[:id], text: 'User message')
      expect(result[:ok]).to be true
    end

    it 'appends agent messages with status' do
      result = ops.append_agent(session_id: session[:id], agent_name: 'a1', text: 'Agent reply', status: 'ok')
      expect(result[:ok]).to be true
    end
  end

  describe '#session_mode and #set_session_mode' do
    let(:session) { ops.session_create(title: 'Mode Test', agents: ['a1']) }

    it 'returns chat mode by default' do
      mode = ops.session_mode(session_id: session[:id])
      expect(mode).to eq('chat')
    end

    it 'sets mode to council' do
      result = ops.set_session_mode(session_id: session[:id], mode: 'council')
      expect(result[:ok]).to be true
      expect(result[:mode]).to eq('council')
    end

    it 'validates mode values' do
      result = ops.set_session_mode(session_id: session[:id], mode: 'invalid')
      expect(result[:mode]).to eq('chat') # Falls back to chat
    end
  end

  describe '#escalate_to_council' do
    let(:session) { ops.session_create(title: 'Escalate Test', agents: ['a1', 'a2']) }

    before do
      ops.append_user(session_id: session[:id], text: 'Should we use microservices or monolith?')
      ops.append_agent(session_id: session[:id], agent_name: 'a1', text: 'That depends on your scale.', status: 'ok')
    end

    it 'requires at least 2 agents' do
      single_agent_session = ops.session_create(title: 'Single Agent', agents: ['a1'])
      expect { ops.escalate_to_council(session_id: single_agent_session[:id], query: 'Test') }
        .to raise_error(/insufficient_agents/)
    end

    it 'escalates session to council mode' do
      result = ops.escalate_to_council(session_id: session[:id], query: 'Decide: microservices or monolith?')
      expect(result[:ok]).to be true
      expect(result[:mode]).to eq('council')
      expect(result[:run_id]).to start_with('council-')
    end

    it 'creates a council run record' do
      result = ops.escalate_to_council(session_id: session[:id], query: 'Test query')
      run = ops.get_council_run(run_id: result[:run_id])
      expect(run).not_to be_nil
      expect(run[:status]).to eq('pending')
      expect(run[:phase]).to eq('init')
    end

    it 'extracts context from conversation' do
      result = ops.escalate_to_council(session_id: session[:id])
      expect(result[:context]).to have_key(:conversation_summary)
      expect(result[:context][:conversation_summary]).to include('microservices')
    end
  end

  describe '#current_council_run' do
    let(:session) { ops.session_create(title: 'Run Test', agents: ['a1', 'a2']) }

    it 'returns nil when no runs exist' do
      run = ops.current_council_run(session[:id])
      expect(run).to be_nil
    end

    it 'returns the latest run' do
      ops.escalate_to_council(session_id: session[:id], query: 'First query')
      ops.return_to_chat(session_id: session[:id])
      ops.escalate_to_council(session_id: session[:id], query: 'Second query')

      run = ops.current_council_run(session[:id])
      expect(run[:query]).to eq('Second query')
    end
  end

  describe '#list_council_runs' do
    let(:session) { ops.session_create(title: 'List Runs Test', agents: ['a1', 'a2']) }

    before do
      3.times do |i|
        ops.escalate_to_council(session_id: session[:id], query: "Query #{i}")
        ops.return_to_chat(session_id: session[:id])
      end
    end

    it 'lists all runs for a session' do
      runs = ops.list_council_runs(session_id: session[:id])
      expect(runs.length).to eq(3)
    end

    it 'respects limit parameter' do
      runs = ops.list_council_runs(session_id: session[:id], limit: 2)
      expect(runs.length).to eq(2)
    end
  end

  describe '#return_to_chat' do
    let(:session) { ops.session_create(title: 'Return Test', agents: ['a1', 'a2']) }

    before do
      ops.escalate_to_council(session_id: session[:id], query: 'Test')
    end

    it 'returns session to chat mode' do
      result = ops.return_to_chat(session_id: session[:id])
      expect(result[:ok]).to be true
      expect(result[:mode]).to eq('chat')
    end

    it 'appends a system message when provided' do
      ops.return_to_chat(session_id: session[:id], message: 'Council complete')
      session_data = ops.session_get(id: session[:id])
      system_msg = session_data[:messages].find { |m| m[:agent_name] == 'System' && m[:text].include?('chat mode') }
      expect(system_msg).not_to be_nil
    end
  end

  describe '#council_status' do
    let(:session) { ops.session_create(title: 'Status Test', agents: ['a1', 'a2']) }

    it 'returns status for chat mode session' do
      status = ops.council_status(session_id: session[:id])
      expect(status[:mode]).to eq('chat')
      expect(status[:council_run]).to be_nil
      expect(status[:roles]).to be_an(Array)
    end

    it 'returns status for council mode session' do
      ops.escalate_to_council(session_id: session[:id], query: 'Test')
      status = ops.council_status(session_id: session[:id])
      expect(status[:mode]).to eq('council')
      expect(status[:council_run]).not_to be_nil
    end
  end

  describe '#session_delete' do
    it 'deletes session and all related data' do
      session = ops.session_create(title: 'Delete Test', agents: ['a1', 'a2'])
      ops.append_user(session_id: session[:id], text: 'Test')
      ops.escalate_to_council(session_id: session[:id], query: 'Test')

      result = ops.session_delete(id: session[:id])
      expect(result[:ok]).to be true

      expect { ops.session_get(id: session[:id]) }.to raise_error('not_found')
    end
  end

  describe 'COUNCIL_ROLES constant' do
    it 'defines all required roles' do
      roles = Savant::Council::COUNCIL_ROLES
      expect(roles.keys).to match_array(%w[analyst skeptic pragmatist safety moderator])
    end

    it 'each role has required fields' do
      Savant::Council::COUNCIL_ROLES.each do |key, role|
        expect(role).to have_key(:name), "#{key} missing :name"
        expect(role).to have_key(:description), "#{key} missing :description"
        expect(role).to have_key(:system_prompt), "#{key} missing :system_prompt"
      end
    end

    it 'safety role mentions veto authority' do
      safety = Savant::Council::COUNCIL_ROLES['safety']
      expect(safety[:system_prompt]).to include('VETO')
    end

    it 'moderator role mentions synthesis' do
      moderator = Savant::Council::COUNCIL_ROLES['moderator']
      expect(moderator[:system_prompt]).to include('Synthesize')
    end
  end

  describe 'private helper methods' do
    describe '#summarize_conversation' do
      it 'creates a summary of messages' do
        session = ops.session_create(title: 'Summary Test', agents: ['a1'])
        ops.append_user(session_id: session[:id], text: 'Hello world')
        ops.append_agent(session_id: session[:id], agent_name: 'a1', text: 'Hi there')

        session_data = ops.session_get(id: session[:id])
        summary = ops.send(:summarize_conversation, session_data[:messages])
        expect(summary).to include('User:')
        expect(summary).to include('Hello world')
      end
    end

    describe '#safe_json_parse' do
      it 'parses valid JSON' do
        result = ops.send(:safe_json_parse, '{"key": "value"}')
        expect(result).to eq({ 'key' => 'value' })
      end

      it 'returns nil for invalid JSON' do
        result = ops.send(:safe_json_parse, 'not json')
        expect(result).to be_nil
      end

      it 'returns hash/array as-is' do
        result = ops.send(:safe_json_parse, { already: 'hash' })
        expect(result).to eq({ already: 'hash' })
      end
    end
  end
end
