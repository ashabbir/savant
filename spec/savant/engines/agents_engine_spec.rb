#!/usr/bin/env ruby
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/savant/engines/agents/ops'

RSpec.describe Savant::Agents::Ops do
  class FakeDB
    attr_reader :agents, :personas, :rulesets, :runs

    def initialize
      @agents = []
      @personas = []
      @rulesets = []
      @runs = []
      @seq = 0
    end

    def exec_params(sql, params)
      case sql
      when /SELECT id FROM personas WHERE name=/
        name = params[0]
        row = @personas.find { |p| p[:name] == name }
        FakeRes.new(row ? [{ 'id' => row[:id].to_s }] : [])
      when /INSERT INTO personas/
        @seq += 1
        @personas << { id: @seq, name: params[0] }
        FakeRes.new([{ 'id' => @seq.to_s }])
      when /SELECT id FROM agents WHERE name=/
        name = params[0]
        row = @agents.find { |a| a[:name] == name }
        FakeRes.new(row ? [{ 'id' => row[:id].to_s }] : [])
      when /SELECT \* FROM agent_runs WHERE id=/
        id = params[0].to_i
        aid = params[1].to_i
        row = @runs.find { |r| r[:id] == id && r[:agent_id] == aid }
        FakeRes.new(row ? [row.transform_keys(&:to_s)] : [])
      else
        FakeRes.new([])
      end
    end

    def exec(_sql)
      FakeRes.new([])
    end

    def create_ruleset(name, content)
      row = @rulesets.find { |r| r[:name] == name }
      return row[:id] if row

      @seq += 1
      @rulesets << { id: @seq, name: name, content: content }
      @seq
    end

    def get_ruleset_by_name(name)
      row = @rulesets.find { |r| r[:name] == name }
      row&.transform_keys(&:to_s)
    end

    def create_agent(name:, persona_id: nil, driver_prompt: nil, driver_name: nil, rule_set_ids: [], favorite: false)
      row = @agents.find { |a| a[:name] == name }
      if row
        row[:persona_id] = persona_id unless persona_id.nil?
        row[:driver_prompt] = driver_prompt unless driver_prompt.nil?
        row[:driver_name] = driver_name unless driver_name.nil?
        row[:rule_set_ids] = rule_set_ids unless rule_set_ids.nil?
        row[:favorite] = !favorite.nil? unless favorite.nil?
      else
        @seq += 1
        row = { id: @seq, name: name, persona_id: persona_id, driver_prompt: driver_prompt, driver_name: driver_name, rule_set_ids: rule_set_ids, favorite: !favorite.nil?, run_count: 0, created_at: Time.now.utc.iso8601, updated_at: Time.now.utc.iso8601 }
        @agents << row
      end
      row[:id]
    end

    def get_agent(id)
      row = @agents.find { |a| a[:id] == id }
      row && stringify(row)
    end

    def find_agent_by_name(name)
      row = @agents.find { |a| a[:name] == name }
      row && stringify(row)
    end

    def list_agents
      @agents.map { |a| stringify(a) }
    end

    def delete_agent_by_name(name)
      before = @agents.length
      @agents.reject! { |a| a[:name] == name }
      before - @agents.length
    end

    def increment_agent_run_count(agent_id)
      row = @agents.find { |a| a[:id] == agent_id }
      row[:run_count] += 1 if row
    end

    def record_agent_run(agent_id:, input:, output_summary:, status:, duration_ms:, full_transcript: nil)
      @seq += 1
      @runs << { id: @seq, agent_id: agent_id, input: input, output_summary: output_summary, status: status, duration_ms: duration_ms, full_transcript: full_transcript, created_at: Time.now.utc.iso8601 }
      @seq
    end

    def list_agent_runs(agent_id, limit: 50)
      @runs.select { |r| r[:agent_id] == agent_id }.last(limit).map { |r| stringify(r) }
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
        else v
        end
      end.transform_keys(&:to_s)
    end
  end

  let(:db) { FakeDB.new }
  let(:ops) { described_class.new(db: db, base_path: Dir.mktmpdir('savant-agents')) }

  it 'creates, lists, gets and deletes agents' do
    created = ops.create(name: 'alpha', persona: 'savant-engineer', driver: 'Do things', rules: ['default'], favorite: true)
    expect(created[:name]).to eq('alpha')
    expect(created[:favorite]).to be true
    list = ops.list
    expect(list.map { |a| a[:name] }).to include('alpha')
    got = ops.get(name: 'alpha')
    expect(got[:driver]).to eq('Do things')
    ok = ops.delete(name: 'alpha')
    expect(ok).to be true
    expect(ops.list).to be_empty
  end

  it 'updates persona, driver, rules and favorite' do
    ops.create(name: 'beta', persona: 'savant-engineer', driver: 'A', rules: ['r1'], favorite: false)
    upd = ops.update(name: 'beta', persona: 'architect', driver: 'B', rules: %w[r2 r3], favorite: true)
    expect(upd[:favorite]).to be true
    expect(upd[:driver]).to eq('B')
    expect(upd[:rule_set_ids].length).to eq(2)
  end

  it 'runs an agent in dry-run and records a run' do
    ops.create(name: 'gamma', persona: 'savant-engineer', driver: 'C', rules: [])
    res = ops.run(name: 'gamma', input: 'say hi', max_steps: 1, dry_run: true)
    expect(res[:status]).to eq('ok')
    runs = ops.runs_list(name: 'gamma', limit: 10)
    expect(runs.length).to eq(1)
    detail = ops.run_read(name: 'gamma', run_id: runs.first[:id])
    expect(detail[:id]).to eq(runs.first[:id])
  end
end
