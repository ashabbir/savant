#!/usr/bin/env ruby
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/savant/engines/agents/ops'
require 'tmpdir'

RSpec.describe 'Agents runs_list fallback behavior' do

  # Reuse the FakeDB defined in agents_engine_spec when available; otherwise define a minimal one here.
  unless defined?(FakeDB)
    class FakeDB
      def initialize
        @agents = {}
        @runs = []
        @seq = 0
      end

      def create_agent(name:, persona_id: nil, driver_prompt: nil, driver_name: nil, rule_set_ids: [], favorite: false, instructions: nil, model_id: nil)
        @seq += 1
        @agents[name] = { 'id' => @seq, 'name' => name, 'persona_id' => persona_id, 'driver_prompt' => driver_prompt, 'driver_name' => driver_name, 'rule_set_ids' => rule_set_ids, 'favorite' => favorite, 'instructions' => instructions, 'model_id' => model_id }
        @seq
      end

      def get_agent(id)
        @agents.values.find { |a| a['id'] == id }
      end

      def find_agent_by_name(name)
        @agents[name]
      end

      def list_agent_runs(agent_id, limit: 50)
        @runs.select { |r| r['agent_id'] == agent_id }.last(limit)
      end

      def record_agent_run(agent_id:, input:, output_summary:, status:, duration_ms:, full_transcript: nil)
        @seq += 1
        @runs << { 'id' => @seq, 'agent_id' => agent_id, 'input' => input, 'output_summary' => output_summary, 'status' => status, 'duration_ms' => duration_ms, 'full_transcript' => full_transcript, 'created_at' => Time.now.utc.iso8601 }
        @seq
      end

      def exec_params(_sql, _params)
        FakeRes.new([])
      end

      class FakeRes
        def initialize(rows) = (@rows = rows)
        def [](i) = @rows[i]
        def ntuples = @rows.length
        def to_a = @rows
      end
    end
  end

  class FakeMongoCol
    def initialize(docs)
      @docs = docs
    end
    def find(_filter)
      self
    end
    def sort(_spec)
      self
    end
    def limit(_n)
      self
    end
    def to_a
      @docs
    end
  end

  let(:db) { FakeDB.new }
  let(:ops) { Savant::Agents::Ops.new(db: db, base_path: Dir.mktmpdir('savant-agents')) }

  before do
    # Create an agent and a DB-only run (simulate Mongo insert failure)
    id = db.create_agent(name: 'searcher phi3')
    db.record_agent_run(agent_id: id, input: 'q', output_summary: 'ok', status: 'running', duration_ms: 10, full_transcript: { steps: [] })
  end

  it 'falls back to DB when Mongo returns no docs' do
    # Simulate Mongo available but empty collection for this agent
    allow(ops).to receive(:agent_runs_col).and_return(FakeMongoCol.new([]))
    runs = ops.send(:runs_list, name: 'searcher phi3', limit: 50)
    expect(runs).not_to be_empty
    expect(runs.first[:input]).to eq('q')
  end

  it 'uses Mongo docs when present' do
    doc = { 'run_id' => 999, 'agent_id' => db.find_agent_by_name('searcher phi3')['id'].to_i, 'input' => 'm', 'status' => 'running', 'created_at' => Time.now.utc }
    allow(ops).to receive(:agent_runs_col).and_return(FakeMongoCol.new([doc]))
    runs = ops.send(:runs_list, name: 'searcher phi3', limit: 50)
    expect(runs.first[:id]).to eq(999)
    expect(runs.first[:input]).to eq('m')
  end

  it 'returns merged unique list when both sources present' do
    agent_id = db.find_agent_by_name('searcher phi3')['id']
    # DB row id 10
    db.record_agent_run(agent_id: agent_id, input: 'db', output_summary: 'ok', status: 'ok', duration_ms: 1, full_transcript: { steps: [] })
    # Mongo row id 20
    doc = { 'run_id' => 20, 'agent_id' => agent_id, 'input' => 'mg', 'status' => 'ok', 'created_at' => Time.now.utc }
    allow(ops).to receive(:agent_runs_col).and_return(FakeMongoCol.new([doc]))
    runs = ops.send(:runs_list, name: 'searcher phi3', limit: 50)
    ids = runs.map { |r| r[:id] }
    expect(ids).to include(20)
    expect(ids.uniq.length).to eq(ids.length)
  end
end
