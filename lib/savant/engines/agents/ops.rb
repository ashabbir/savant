#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'time'
require_relative '../../framework/db'
require_relative '../../framework/boot'
require_relative '../../agent/runtime'

module Savant
  module Agents
    # Implements agents CRUD using DB and orchestrates runs using Agent::Runtime.
    class Ops
      def initialize(db: nil, base_path: nil)
        @db = db || Savant::Framework::DB.new
        @base_path = base_path || default_base_path
      end

      def list
        rows = @db.list_agents
        rows.map { |r| to_agent_hash(r) }
      end

      def get(name:)
        row = @db.find_agent_by_name(name)
        raise 'not_found' unless row
        to_agent_hash(row)
      end

      def create(name:, persona:, driver:, rules: [], favorite: false)
        persona_id = ensure_persona(name: persona)
        rule_ids = ensure_rules(rules)
        id = @db.create_agent(name: name, persona_id: persona_id, driver_prompt: driver, rule_set_ids: rule_ids, favorite: favorite)
        row = @db.get_agent(id)
        to_agent_hash(row)
      end

      def update(name:, persona: nil, driver: nil, rules: nil, favorite: nil)
        row = @db.find_agent_by_name(name)
        raise 'not_found' unless row
        persona_id = row['persona_id']
        persona_id = ensure_persona(name: persona) if !persona.nil? && !persona.to_s.strip.empty?
        rule_ids = nil
        rule_ids = ensure_rules(rules) if rules.is_a?(Array)

        # Build update via create_agent upsert semantics
        id = @db.create_agent(
          name: name,
          persona_id: persona_id,
          driver_prompt: driver.nil? ? row['driver_prompt'] : driver,
          rule_set_ids: rule_ids || parse_int_array(row['rule_set_ids']),
          favorite: favorite.nil? ? (row['favorite'] == 't' || row['favorite'] == true) : !!favorite
        )
        got = @db.get_agent(id)
        to_agent_hash(got)
      end

      def delete(name:)
        @db.delete_agent_by_name(name) > 0
      end

      def run(name:, input:, max_steps: nil, dry_run: false)
        agent = @db.find_agent_by_name(name)
        raise 'not_found' unless agent

        # Boot core runtime using selected persona; then override driver prompt to agent's driver
        context = Savant::Boot.initialize!(persona_name: persona_name(agent), skip_git: true, base_path: @base_path)
        context.driver_prompt = { version: 'agent', prompt_md: (agent['driver_prompt'] || '').to_s }

        rt = Savant::Agent::Runtime.new(goal: input.to_s, base_path: @base_path)
        started = monotonic
        res = rt.run(max_steps: (max_steps || Savant::Agent::Runtime::DEFAULT_MAX_STEPS).to_i, dry_run: dry_run)
        dur_ms = ((monotonic - started) * 1000.0).round

        # Persist run
        begin
          # Update counters
          @db.increment_agent_run_count(agent['id'])

          # Read transcript JSON from memory file if exists
          transcript = nil
          if res.is_a?(Hash)
            mpath = res[:memory_path] || res['memory_path']
            if mpath && File.file?(mpath)
              transcript = JSON.parse(File.read(mpath)) rescue nil
            end
          end
          summary = res[:final] || res['final'] || nil
          status = res[:status] || res['status'] || 'ok'
          @db.record_agent_run(agent_id: agent['id'], input: input.to_s, output_summary: summary, status: status, duration_ms: dur_ms, full_transcript: transcript)
        rescue StandardError
          # best-effort
        end

        { status: 'ok', duration_ms: dur_ms, result: res }
      rescue StandardError => e
        { status: 'error', error: e.message }
      end

      def runs_list(name:, limit: 50)
        agent = @db.find_agent_by_name(name)
        raise 'not_found' unless agent
        rows = @db.list_agent_runs(agent['id'], limit: limit)
        rows.map do |r|
          {
            id: r['id'].to_i,
            input: r['input'],
            output_summary: r['output_summary'],
            status: r['status'],
            duration_ms: r['duration_ms']&.to_i,
            created_at: r['created_at']
          }
        end
      end

      def run_read(name:, run_id:)
        agent = @db.find_agent_by_name(name)
        raise 'not_found' unless agent
        res = @db.exec_params('SELECT * FROM agent_runs WHERE id=$1 AND agent_id=$2', [run_id.to_i, agent['id']])
        raise 'not_found' if res.ntuples.zero?
        row = res[0]
        payload = row['full_transcript']
        parsed = begin
          payload && !payload.to_s.empty? ? JSON.parse(payload) : nil
        rescue StandardError
          nil
        end
        { id: row['id'].to_i, transcript: parsed }
      end

      private
      def default_base_path
        if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
          ENV['SAVANT_PATH']
        else
          File.expand_path('../../../..', __dir__)
        end
      end

      def ensure_persona(name:)
        return nil if name.to_s.strip.empty?
        row = @db.exec_params('SELECT id FROM personas WHERE name=$1', [name])
        return row[0]['id'].to_i if row.ntuples.positive?
        @db.create_ruleset('__noop__', '') # ensure encoders warmed up
        res = @db.exec_params('INSERT INTO personas(name, content) VALUES($1,$2) RETURNING id', [name, nil])
        res[0]['id'].to_i
      end

      def ensure_rules(rules)
        list = Array(rules).map(&:to_s).reject(&:empty?)
        ids = []
        list.each do |name|
          got = @db.get_ruleset_by_name(name)
          if got
            ids << got['id'].to_i
          else
            ids << @db.create_ruleset(name, nil)
          end
        end
        ids
      end

      def persona_name(agent_row)
        pid = agent_row['persona_id']
        return 'savant-engineer' unless pid
        res = @db.exec_params('SELECT name FROM personas WHERE id=$1', [pid])
        res.ntuples.positive? ? res[0]['name'] : 'savant-engineer'
      end

      def to_agent_hash(row)
        {
          id: row['id'].to_i,
          name: row['name'],
          persona_id: row['persona_id']&.to_i,
          driver: row['driver_prompt'],
          rule_set_ids: parse_int_array(row['rule_set_ids']),
          favorite: row['favorite'] == 't' || row['favorite'] == true,
          run_count: row['run_count']&.to_i,
          last_run_at: row['last_run_at'],
          created_at: row['created_at'],
          updated_at: row['updated_at']
        }
      end

      def parse_int_array(pg_array_text)
        return [] if pg_array_text.nil?
        # PG returns like "{1,2,3}"; quick parse
        pg_array_text.to_s.delete('{}').split(',').map { |s| s.to_i }
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end

