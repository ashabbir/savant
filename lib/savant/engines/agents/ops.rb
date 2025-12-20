#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'time'
require_relative '../../framework/db'
require_relative '../../framework/boot'
require_relative '../../agent/runtime'
require_relative '../drivers/ops'
require_relative '../llm/vault'

module Savant
  module Agents
    # Implements agents CRUD using DB and orchestrates runs using Agent::Runtime.
    class Ops
      def initialize(db: nil, base_path: nil)
        @db = db || Savant::Framework::DB.new
        @base_path = base_path || default_base_path
      end
      
      # --- Mongo helpers ---
      def mongo_available?
        return @mongo_available if defined?(@mongo_available)
        begin
          require 'mongo'
          @mongo_available = true
        rescue LoadError
          @mongo_available = false
        end
        @mongo_available
      end

      def mongo_client
        return nil unless mongo_available?
        now = Time.now
        return nil if @mongo_disabled_until && now < @mongo_disabled_until
        if defined?(@mongo_client) && @mongo_client
          return @mongo_client
        end
        begin
          uri = ENV.fetch('MONGO_URI', "mongodb://#{mongo_host}/#{mongo_db_name}")
          client = Mongo::Client.new(uri, server_selection_timeout: 1.5, connect_timeout: 1.5, socket_timeout: 2)
          client.database.collections
          @mongo_client = client
        rescue StandardError
          @mongo_disabled_until = now + 10
          @mongo_client = nil
        end
        @mongo_client
      end

      def mongo_host
        ENV.fetch('MONGO_HOST', 'localhost:27017')
      end

      def mongo_db_name
        env = ENV.fetch('SAVANT_ENV', ENV.fetch('RACK_ENV', ENV.fetch('RAILS_ENV', 'development')))
        env == 'test' ? 'savant_test' : 'savant_development'
      end

      def agent_runs_col
        c = mongo_client
        c ? c[:agent_runs] : nil
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

      def create(name:, persona:, driver:, rules: [], favorite: false, instructions: nil)
        persona_id = ensure_persona(name: persona)
        rule_ids = ensure_rules(rules)
        id = @db.create_agent(name: name, persona_id: persona_id, driver_name: driver, rule_set_ids: rule_ids, favorite: favorite, instructions: instructions)
        row = @db.get_agent(id)
        to_agent_hash(row)
      end

      def update(name:, persona: nil, driver: nil, rules: nil, favorite: nil, instructions: nil, model_id: nil)
        row = @db.find_agent_by_name(name)
        raise 'not_found' unless row

        persona_id = row['persona_id']
        persona_id = ensure_persona(name: persona) if !persona.nil? && !persona.to_s.strip.empty?
        rule_ids = nil
        rule_ids = ensure_rules(rules) if rules.is_a?(Array)

        # Validate model_id if provided (must exist in llm_models table)
        final_model_id = if model_id.nil?
          row['model_id']
        else
          model_id
        end

        # Build update via create_agent upsert semantics
        fav = if favorite.nil?
          ['t', true].include?(row['favorite'])
        else
          # Coerce to strict boolean to avoid truthiness surprises
          [true, 'true', '1', 't', 'yes', 'y'].include?(favorite)
        end
        begin
          log = Savant::Logging::MongoLogger.new(service: 'agents')
          log.info(event: 'agents.update', name: name, favorite_in: favorite, favorite_old: row['favorite'], favorite_final: fav)
        rescue StandardError
        end
        id = @db.create_agent(
          name: name,
          persona_id: persona_id,
          driver_prompt: row['driver_prompt'],
          driver_name: driver.nil? ? row['driver_name'] : driver,
          rule_set_ids: rule_ids || parse_int_array(row['rule_set_ids']),
          favorite: fav,
          instructions: instructions.nil? ? row['instructions'] : instructions,
          model_id: final_model_id
        )
        got = @db.get_agent(id)
        to_agent_hash(got)
      end

      def delete(name:)
        @db.delete_agent_by_name(name).positive?
      end

      def run(name:, input:, max_steps: nil, dry_run: false, user_id: nil, pre_run_id: nil, system_message: nil)
        agent = @db.find_agent_by_name(name)
        raise 'not_found' unless agent

        # In dry-run, avoid full boot dependencies; set up a minimal runtime and finish immediately.
        if dry_run
          # Ensure minimal runtime context exists
          if Savant::Framework::Runtime.current.nil?
            Savant::Framework::Runtime.current = Savant::RuntimeContext.new(
              session_id: "dry_#{Time.now.to_i}",
              persona: { name: 'savant-engineer', version: 'dry', prompt_md: '' },
              driver_prompt: nil,
              amr_rules: { version: 'dry', rules: [] },
              repo: nil,
              memory: {},
              logger: Savant::Logging::MongoLogger.new(service: 'agent', io: nil),
              multiplexer: nil
            )
          end
        else
          # Boot core runtime using selected persona; then override driver prompt to agent's driver
          context = Savant::Boot.initialize!(persona_name: persona_name(agent), skip_git: true, base_path: @base_path)

          # Resolve driver: prefer Drivers engine by name; fallback to raw prompt text if not found
          raw = (agent['driver_prompt'] || '').to_s
          driver_prompt = nil
          unless raw.empty?
            begin
              drv = Savant::Drivers::Ops.new(root: @base_path).get(name: raw)
              driver_prompt = { version: drv[:version], prompt_md: drv[:prompt_md], name: drv[:name] } if drv && drv[:prompt_md]
            rescue StandardError
              driver_prompt = nil
            end
          end
          # Fallback: if raw looks like a prompt (multi-line or long), use it directly for backward compatibility
          driver_prompt = { version: 'legacy', prompt_md: raw } if driver_prompt.nil? && !raw.empty? && (raw.include?("\n") || raw.length > 120)
          context.driver_prompt = driver_prompt if driver_prompt
        end

        # Clear any stale agent-wide cancellation before starting
        begin
          Savant::Agent::Cancel.clear(Savant::Agent::Cancel.key_for(agent_name: name, user_id: user_id))
        rescue StandardError
        end
        # For dry-run, force an immediate finish to avoid LLM/tool calls.
        forced_finish = dry_run ? true : false
        forced_final = dry_run ? 'Dry run complete.' : nil
        # Configure runtime with agent-specific LLM settings if assigned
        llm_model_name = nil
        llm_provider = nil
        llm_api_key = nil
        begin
          if agent['model_id']
            res = @db.exec_params('SELECT m.*, p.name as provider_name, p.encrypted_api_key, p.api_key_nonce, p.api_key_tag FROM llm_models m JOIN llm_providers p ON p.id = m.provider_id WHERE m.id = $1', [agent['model_id']])
            if res.ntuples.positive?
              row = res[0]
              # Use provider_model_id for actual API calls, display_name is just for UI
              llm_model_name = row['provider_model_id']
              llm_provider = row['provider_name']
              # Decrypt API key if available
              if row['encrypted_api_key'] && row['api_key_nonce'] && row['api_key_tag']
                begin
                  ciphertext = row['encrypted_api_key']
                  nonce = row['api_key_nonce']
                  tag = row['api_key_tag']

                  # Handle double-hex encoding from PostgreSQL BYTEA
                  if ciphertext.is_a?(String) && ciphertext.start_with?('\\x')
                    hex_str = [ciphertext[2..-1]].pack('H*')
                    ciphertext = [hex_str].pack('H*')
                  end
                  if nonce.is_a?(String) && nonce.start_with?('\\x')
                    hex_str = [nonce[2..-1]].pack('H*')
                    nonce = [hex_str].pack('H*')
                  end
                  if tag.is_a?(String) && tag.start_with?('\\x')
                    hex_str = [tag[2..-1]].pack('H*')
                    tag = [hex_str].pack('H*')
                  end

                  llm_api_key = Savant::Llm::Vault.decrypt(ciphertext, nonce, tag)
                rescue StandardError
                  # If decryption fails, proceed without API key
                end
              end
            end
          end
        rescue StandardError
          llm_model_name = nil
          llm_provider = nil
          llm_api_key = nil
        end

        # Persist a Mongo placeholder and/or pre-create a DB row so the run has an id immediately
        run_id = pre_run_id
        if run_id.nil?
          begin
            # DB: create minimal run row with status=running
            run_id = @db.record_agent_run(
              agent_id: agent['id'],
              input: input.to_s,
              output_summary: nil,
              status: 'running',
              duration_ms: nil,
              full_transcript: nil
            )
          rescue StandardError
            run_id = nil
          end
          begin
            if (col = agent_runs_col)
              col.insert_one({
                run_id: run_id,
                agent_id: agent['id'].to_i,
                agent_name: agent['name'],
                input: input.to_s,
                status: 'running',
                created_at: Time.now.utc,
                started_at: Time.now.utc
              })
            end
          rescue StandardError
            # best-effort only
          end
        end

        # Use a run-scoped cancellation key so we can cancel individual runs
        cancel_key_run = Savant::Agent::Cancel.key_for_run(agent_name: name, run_id: run_id || 0, user_id: user_id)
        begin
          Savant::Agent::Cancel.clear(cancel_key_run)
        rescue StandardError
        end
        rt = Savant::Agent::Runtime.new(goal: input.to_s, base_path: @base_path, cancel_key: cancel_key_run,
                                        forced_finish: forced_finish, forced_final: forced_final,
                                        llm_model: llm_model_name, run_id: run_id)
        # Seed a system message (e.g., prior run transcript summary) if provided
        begin
          rt.system_message = system_message if system_message && !system_message.to_s.empty?
        rescue StandardError
        end
        # Pass through any saved agent-specific instructions into the runtime prompt
        begin
          rt.agent_instructions = agent['instructions']
        rescue StandardError
          rt.agent_instructions = nil
        end
        # Pass through agent-specific rulesets content to runtime for Reasoning API context
        begin
          rule_ids = parse_int_array(agent['rule_set_ids'])
          unless rule_ids.empty?
            param = "{#{rule_ids.join(',')}}"
            rows = @db.exec_params('SELECT id, name, version, summary, rules_md FROM rulesets WHERE id = ANY($1::int[]) ORDER BY name ASC', [param])
            rt.agent_rulesets = rows.map do |r|
              {
                id: r['id'].to_i,
                name: r['name'],
                version: r['version']&.to_i,
                summary: r['summary'],
                rules_md: r['rules_md']
              }
            end
          end
        rescue StandardError
          rt.agent_rulesets = nil
        end
        # Carry provider, model, and API key for reasoning API
        begin
          if llm_model_name
            rt.agent_llm = { llm_model: llm_model_name, provider: llm_provider }
            rt.agent_llm[:api_key] = llm_api_key if llm_api_key
          end
        rescue StandardError
          # ignore
        end
        begin
          Savant::Logging::EventRecorder.global.record({ type: 'agent_run_started', mcp: 'agent', agent: name, goal: input.to_s, ts: Time.now.utc.iso8601, timestamp: Time.now.to_i })
        rescue StandardError
          # ignore telemetry errors
        end
        started = monotonic

        res = rt.run(max_steps: (max_steps || Savant::Agent::Runtime::DEFAULT_MAX_STEPS).to_i, dry_run: dry_run)
        dur_ms = ((monotonic - started) * 1000.0).round

        # Persist run
        begin
          # Update counters
          @db.increment_agent_run_count(agent['id'])

          # Prefer full transcript returned by runtime; fallback to snapshot file if needed
          transcript = nil
          if res.is_a?(Hash)
            transcript = res[:transcript] || res['transcript']
            if transcript.nil?
              mpath = res[:memory_path] || res['memory_path']
              if mpath && File.file?(mpath)
                transcript = begin
                  JSON.parse(File.read(mpath))
                rescue StandardError
                  nil
                end
              end
            end
          end
          # Prefer final, else error text for visibility
          summary = res[:final] || res['final'] || res[:error] || res['error'] || nil
          status = res[:status] || res['status'] || 'ok'

          # Update DB row if it was created earlier, else insert fresh
          if run_id
            begin
              @db.update_agent_run_result(run_id: run_id, agent_id: agent['id'], output_summary: summary, status: status, duration_ms: dur_ms, full_transcript: transcript)
            rescue StandardError
              # fallback to insert
              run_id = @db.record_agent_run(agent_id: agent['id'], input: input.to_s, output_summary: summary, status: status, duration_ms: dur_ms, full_transcript: transcript)
            end
          else
            run_id = @db.record_agent_run(agent_id: agent['id'], input: input.to_s, output_summary: summary, status: status, duration_ms: dur_ms, full_transcript: transcript)
          end

          # Mirror to Mongo (best-effort)
          begin
            if (col = agent_runs_col)
              col.update_one(
                { agent_id: agent['id'].to_i, run_id: run_id },
                {
                  '$set' => {
                    run_id: run_id,
                    agent_id: agent['id'].to_i,
                    agent_name: agent['name'],
                    input: input.to_s,
                    output_summary: summary,
                    status: status.to_s,
                    duration_ms: dur_ms.to_i,
                    transcript: transcript,
                    completed_at: Time.now.utc
                  },
                  '$setOnInsert' => { created_at: Time.now.utc }
                },
                { upsert: true }
              )
            end
          rescue StandardError
            # ignore Mongo errors
          end
        rescue StandardError
          # best-effort
        end

        begin
          Savant::Logging::EventRecorder.global.record({ type: 'agent_run_completed', mcp: 'agent', agent: name, status: 'ok', duration_ms: dur_ms, ts: Time.now.utc.iso8601, timestamp: Time.now.to_i })
        rescue StandardError
        end
        { status: 'ok', duration_ms: dur_ms, result: res }
      rescue StandardError => e
        # Update persisted placeholders with error status
        begin
          dur_ms = ((monotonic - started) * 1000.0).round
          if run_id
            begin
              @db.update_agent_run_result(run_id: run_id, agent_id: agent['id'], output_summary: e.message, status: 'error', duration_ms: dur_ms, full_transcript: nil)
            rescue StandardError
              # ignore
            end
          end
          if (col = agent_runs_col)
            begin
              if run_id
                col.update_one({ agent_id: agent['id'].to_i, run_id: run_id }, { '$set' => { status: 'error', duration_ms: dur_ms.to_i, output_summary: e.message, completed_at: Time.now.utc } })
              else
                col.insert_one({
                  run_id: run_id,
                  agent_id: agent['id'].to_i,
                  agent_name: agent['name'],
                  input: input.to_s,
                  output_summary: e.message,
                  status: 'error',
                  duration_ms: dur_ms.to_i,
                  created_at: Time.now.utc
                })
              end
            rescue StandardError
            end
          end
        rescue StandardError
        end
        begin
          Savant::Logging::EventRecorder.global.record({ type: 'agent_run_completed', mcp: 'agent', agent: name, status: 'error', error: e.message, ts: Time.now.utc.iso8601, timestamp: Time.now.to_i })
        rescue StandardError
        end
        { status: 'error', error: e.message }
      end

      # Submit an agent run asynchronously: pre-create run row + placeholder in Mongo, spawn background thread
      def run_submit(name:, input:, max_steps: nil, dry_run: false, user_id: nil)
        agent = @db.find_agent_by_name(name)
        raise 'not_found' unless agent

        # Clear any stale cancellation flag
        begin
          Savant::Agent::Cancel.clear(Savant::Agent::Cancel.key_for(agent_name: name, user_id: user_id))
        rescue StandardError
        end

        # Pre-create DB row to get run_id
        run_id = nil
        begin
          run_id = @db.record_agent_run(
            agent_id: agent['id'],
            input: input.to_s,
            output_summary: nil,
            status: 'running',
            duration_ms: nil,
            full_transcript: nil
          )
        rescue StandardError
          run_id = nil
        end

        # Insert placeholder into Mongo
        begin
          if (col = agent_runs_col)
            col.insert_one({
              run_id: run_id,
              agent_id: agent['id'].to_i,
              agent_name: agent['name'],
              input: input.to_s,
              status: 'running',
              created_at: Time.now.utc,
              started_at: Time.now.utc
            })
          end
        rescue StandardError
        end

        # Spawn background execution using a fresh Ops instance to avoid thread-sharing DB clients
        Thread.new do
          begin
            ENV['SAVANT_DEV'] = '1'  # Ensure license check is skipped in background threads
            Savant::Agents::Ops.new(base_path: @base_path).run(name: name, input: input, max_steps: max_steps, dry_run: dry_run, user_id: user_id, pre_run_id: run_id)
          rescue StandardError => e
            # Log the error for debugging
            begin
              Savant::Logging::MongoLogger.new(service: 'agents').error("Agent run failed: #{e.class} #{e.message}\n#{e.backtrace.first(5).join("\n")}")
            rescue StandardError
              # Silently ignore logging errors
            end
          end
        end

        { status: 'submitted', run_id: run_id }
      end

      # Submit a follow-up run seeded with a previous run's transcript as context.
      # Creates a new run row, then executes in background with a system message summarizing the prior run.
      def run_continue_submit(name:, from_run_id:, message:, max_steps: nil, user_id: nil)
        agent = @db.find_agent_by_name(name)
        raise 'not_found' unless agent

        # Pre-create DB row for the follow-up run
        new_run_id = nil
        begin
          new_run_id = @db.record_agent_run(
            agent_id: agent['id'],
            input: message.to_s,
            output_summary: nil,
            status: 'running',
            duration_ms: nil,
            full_transcript: nil
          )
        rescue StandardError
          new_run_id = nil
        end

        # Insert placeholder into Mongo
        begin
          if (col = agent_runs_col)
            col.insert_one({
              run_id: new_run_id,
              agent_id: agent['id'].to_i,
              agent_name: agent['name'],
              input: message.to_s,
              status: 'running',
              created_at: Time.now.utc,
              started_at: Time.now.utc,
              continued_from: from_run_id.to_i
            })
          end
        rescue StandardError
        end

        # Spawn background execution that builds a system message from the previous run
        Thread.new do
          begin
            ENV['SAVANT_DEV'] = '1'
            prev = nil
            begin
              prev = run_read(name: name, run_id: from_run_id)
            rescue StandardError
              prev = nil
            end

            sys = build_system_message(prev, from_run_id)

            Savant::Agents::Ops.new(base_path: @base_path).run(
              name: name,
              input: message,
              max_steps: max_steps,
              dry_run: false,
              user_id: user_id,
              pre_run_id: new_run_id,
              system_message: sys
            )
          rescue StandardError => e
            begin
              Savant::Logging::MongoLogger.new(service: 'agents').error("Agent continue failed: #{e.class} #{e.message}\n#{e.backtrace.first(5).join("\n")}")
            rescue StandardError
            end
          end
        end

        { status: 'submitted', run_id: new_run_id }
      end

      private

      def build_system_message(prev_run, from_run_id)
        begin
          return "Follow-up to run ##{from_run_id}." unless prev_run.is_a?(Hash)
          summary = (prev_run[:output_summary] || prev_run['output_summary'] || '').to_s
          transcript = prev_run[:transcript] || prev_run['transcript']
          steps = []
          if transcript.is_a?(Hash)
            arr = transcript[:steps] || transcript['steps'] || []
            steps = arr.is_a?(Array) ? arr : []
          end
          recent = steps.last(6)
          def trunc(s, n)
            str = s.to_s
            return str if str.length <= n
            str[0, n] + '…'
          end
          lines = []
          lines << "Continuing from prior agent run ##{from_run_id}. Use this history as context for the user's follow-up."
          lines << (summary.empty? ? nil : "Previous final: #{trunc(summary, 400)}")
          unless recent.empty?
            lines << "Recent transcript:"
            recent.each do |s|
              idx = s['index'] || s[:index] || '?'
              act = (s['action'] || s[:action] || {})
              a = (act['action'] || act[:action] || '').to_s
              tool = (act['tool_name'] || act[:tool_name] || '').to_s
              fin = (act['final'] || act[:final] || '').to_s
              out = s['output'] || s[:output]
              out_s = out.is_a?(String) ? out : (out.nil? ? '' : out.to_json)
              text = [
                "Step #{idx}: #{a}#{tool.empty? ? '' : " → #{tool}"}",
                (fin.empty? ? nil : "final: #{trunc(fin, 280)}"),
                (out_s.empty? ? nil : "output: #{trunc(out_s, 280)}")
              ].compact.join(' | ')
              lines << "- #{text}"
            end
          end
          lines.compact.join("\n")
        rescue StandardError
          "Follow-up to run ##{from_run_id}."
        end
      end

      public

      public

      # Signal cancellation for an agent run (per user if available)
      def run_cancel(name:, user_id: nil)
        key = Savant::Agent::Cancel.key_for(agent_name: name, user_id: user_id)
        Savant::Agent::Cancel.request(key)
        { ok: true }
      end

      # Signal cancellation for a specific run id
      def run_cancel_id(name:, run_id:, user_id: nil)
        key = Savant::Agent::Cancel.key_for_run(agent_name: name, run_id: run_id, user_id: user_id)
        Savant::Agent::Cancel.request(key)
        # Best-effort cancel at Reasoning transport layer (e.g., Mongo queue)
        begin
          Savant::Reasoning::Client.new.cancel(correlation_id: run_id.to_s)
        rescue StandardError
        end
        { ok: true }
      end

      def runs_list(name:, limit: 50)
        limit_i = [limit.to_i, 200].min
        agent = @db.find_agent_by_name(name)

        mongo_rows = []
        if (col = agent_runs_col)
          begin
            filter = agent ? { agent_id: agent['id'].to_i } : { agent_name: name.to_s }
            docs = col.find(filter).sort({ created_at: -1 }).limit(limit_i).to_a
            mongo_rows = (docs || []).map { |d| mongo_doc_to_run_row(d) }
          rescue StandardError
            mongo_rows = []
          end
        end

        db_rows = []
        begin
          # Prefer name-based join so we don't miss runs due to agent_id mismatch across environments
          sql = <<~SQL
            SELECT ar.* FROM agent_runs ar
            JOIN agents a ON a.id = ar.agent_id
            WHERE a.name = $1
            ORDER BY ar.id DESC
            LIMIT $2
          SQL
          rows = @db.exec_params(sql, [name.to_s, limit_i])
          db_rows = rows.to_a.map { |r| db_run_row_to_hash(r) }
          if db_rows.empty?
            # Case-insensitive retry
            sql2 = <<~SQL
              SELECT ar.* FROM agent_runs ar
              JOIN agents a ON a.id = ar.agent_id
              WHERE lower(a.name) = lower($1)
              ORDER BY ar.id DESC
              LIMIT $2
            SQL
            rows2 = @db.exec_params(sql2, [name.to_s, limit_i])
            db_rows = rows2.to_a.map { |r| db_run_row_to_hash(r) }
          end
          if db_rows.empty? && agent
            # Final fallback by agent_id
            rows3 = @db.list_agent_runs(agent['id'], limit: limit_i)
            db_rows = rows3.map { |r| db_run_row_to_hash(r) }
          end
        rescue StandardError
          db_rows = []
        end

        merged = {}
        (db_rows + mongo_rows).each { |r| merged[r[:id]] ||= r }
        merged.values.sort_by { |r| r[:id] || 0 }.reverse.first(limit_i)
      end

      def db_run_row_to_hash(r)
        steps_count = nil
        final_text = nil
        begin
          if r['full_transcript'] && !r['full_transcript'].to_s.empty?
            t = begin
              JSON.parse(r['full_transcript'])
            rescue StandardError
              nil
            end
            if t.is_a?(Hash)
              steps = t['steps'] || t[:steps] || []
              steps_count = steps.is_a?(Array) ? steps.size : nil
              if steps.is_a?(Array)
                steps.reverse_each do |s|
                  a = s['action'] || s[:action] || {}
                  f = a['final'] || a[:final]
                  if f && !f.to_s.empty?
                    final_text = f.to_s
                    break
                  end
                end
              end
            end
          end
        rescue StandardError
          steps_count = nil
          final_text = nil
        end

        {
          id: r['id'].to_i,
          input: r['input'],
          output_summary: r['output_summary'],
          status: r['status'],
          duration_ms: r['duration_ms']&.to_i,
          created_at: r['created_at'],
          steps: steps_count,
          final: r['output_summary'] && !r['output_summary'].to_s.empty? ? r['output_summary'] : final_text
        }
      end

      def run_read(name:, run_id:)
        agent = @db.find_agent_by_name(name)
        raise 'not_found' unless agent

        # Build agent configuration hash
        agent_config = build_agent_config(agent)

        # Try Mongo first
        if (col = agent_runs_col)
          begin
            d = col.find({ agent_id: agent['id'].to_i, run_id: run_id.to_i }).limit(1).first
            if d
              return {
                id: (d['run_id'] || d[:run_id]).to_i,
                input: d['input'] || d[:input],
                status: d['status'] || d[:status],
                output_summary: d['output_summary'] || d[:output_summary],
                duration_ms: (d['duration_ms'] || d[:duration_ms]).to_i,
                transcript: d['transcript'] || d[:transcript],
                agent: agent_config
              }
            end
          rescue StandardError
            # fall through
          end
        end

        res = @db.exec_params('SELECT * FROM agent_runs WHERE id=$1 AND agent_id=$2', [run_id.to_i, agent['id']])
        raise 'not_found' if res.ntuples.zero?

        row = res[0]
        payload = row['full_transcript']
        parsed = begin
          payload && !payload.to_s.empty? ? JSON.parse(payload) : nil
        rescue StandardError
          nil
        end
        {
          id: row['id'].to_i,
          input: row['input'],
          status: row['status'],
          output_summary: row['output_summary'],
          duration_ms: row['duration_ms']&.to_i,
          transcript: parsed,
          agent: agent_config
        }
      end

      def run_delete(name:, run_id:)
        agent = @db.find_agent_by_name(name)
        raise 'not_found' unless agent
        # Delete from DB
        res = @db.exec_params('DELETE FROM agent_runs WHERE id=$1 AND agent_id=$2', [run_id.to_i, agent['id']])
        ok = res.cmd_tuples.positive?
        # Best-effort delete from Mongo
        begin
          if (col = agent_runs_col)
            col.delete_many({ agent_id: agent['id'].to_i, run_id: run_id.to_i })
          end
        rescue StandardError
        end
        ok
      end

      def runs_clear_all(name:)
        agent = @db.find_agent_by_name(name)
        raise 'not_found' unless agent
        count = 0
        res = @db.exec_params('DELETE FROM agent_runs WHERE agent_id=$1', [agent['id']])
        count = res.cmd_tuples
        begin
          if (col = agent_runs_col)
            col.delete_many({ agent_id: agent['id'].to_i })
          end
        rescue StandardError
        end
        { deleted_count: count }
      end

      private

      def default_base_path
        if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
          ENV['SAVANT_PATH']
        else
          # Expand relative to this file's location to get project root
          # lib/savant/engines/agents/ops.rb -> go up 4 levels to project root
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
          ids << if got
                   got['id'].to_i
                 else
                   @db.create_ruleset(name, nil)
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
        # Lookup persona and ruleset names for better UX in UI
        persona_name = nil
        begin
          if row['persona_id']
            res = @db.exec_params('SELECT name FROM personas WHERE id=$1', [row['persona_id']])
            persona_name = res.ntuples.positive? ? res[0]['name'] : nil
          end
        rescue StandardError
          persona_name = nil
        end

        rule_ids = parse_int_array(row['rule_set_ids'])
        rules_names = []
        begin
          unless rule_ids.empty?
            param = "{#{rule_ids.join(',')}}"
            res = @db.exec_params('SELECT name FROM rulesets WHERE id = ANY($1::int[]) ORDER BY name ASC', [param])
            rules_names = res.map { |r| r['name'] }
          end
        rescue StandardError
          rules_names = []
        end

        {
          id: row['id'].to_i,
          name: row['name'],
          persona_id: row['persona_id']&.to_i,
          persona_name: persona_name,
          driver: row['driver_name'] && !row['driver_name'].to_s.empty? ? row['driver_name'] : row['driver_prompt'],
          instructions: row['instructions'],
          rule_set_ids: rule_ids,
          rules_names: rules_names,
          model_id: row['model_id']&.to_i,
          favorite: ['t', true].include?(row['favorite']),
          run_count: row['run_count']&.to_i,
          last_run_at: row['last_run_at'],
          created_at: row['created_at'],
          updated_at: row['updated_at']
        }
      end

      def parse_int_array(pg_array_text)
        return [] if pg_array_text.nil?

        # PG returns like "{1,2,3}"; quick parse
        pg_array_text.to_s.delete('{}').split(',').map(&:to_i)
      end

      # Build a compact agent config hash for run_read
      def build_agent_config(agent)
        # Lookup persona name
        persona_name = nil
        begin
          if agent['persona_id']
            res = @db.exec_params('SELECT name FROM personas WHERE id=$1', [agent['persona_id']])
            persona_name = res.ntuples.positive? ? res[0]['name'] : nil
          end
        rescue StandardError
          persona_name = nil
        end

        # Lookup rules names
        rule_ids = parse_int_array(agent['rule_set_ids'])
        rules_names = []
        begin
          unless rule_ids.empty?
            param = "{#{rule_ids.join(',')}}"
            res = @db.exec_params('SELECT name FROM rulesets WHERE id = ANY($1::int[]) ORDER BY name ASC', [param])
            rules_names = res.map { |r| r['name'] }
          end
        rescue StandardError
          rules_names = []
        end

        # Lookup model info if model_id is set
        model_name = nil
        model_provider = nil
        begin
          if agent['model_id']
            res = @db.exec_params(
              'SELECT m.display_name, m.provider_model_id, p.name as provider_name FROM llm_models m JOIN llm_providers p ON p.id = m.provider_id WHERE m.id = $1',
              [agent['model_id']]
            )
            if res.ntuples.positive?
              row = res[0]
              model_name = row['display_name'] && !row['display_name'].to_s.strip.empty? ? row['display_name'] : row['provider_model_id']
              model_provider = row['provider_name']
            end
          end
        rescue StandardError
          model_name = nil
          model_provider = nil
        end

        {
          name: agent['name'],
          persona_name: persona_name,
          driver: agent['driver_name'] && !agent['driver_name'].to_s.empty? ? agent['driver_name'] : agent['driver_prompt'],
          rules_names: rules_names,
          model_id: agent['model_id']&.to_i,
          model_name: model_name,
          model_provider: model_provider,
          instructions: agent['instructions']
        }
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def mongo_doc_to_run_row(d)
        transcript = d['transcript'] || d[:transcript]
        steps_count = nil
        final_text = nil
        begin
          if transcript.is_a?(Hash)
            steps = transcript['steps'] || transcript[:steps] || []
            steps_count = steps.is_a?(Array) ? steps.size : nil
            if steps.is_a?(Array)
              steps.reverse_each do |s|
                a = s['action'] || s[:action] || {}
                f = a['final'] || a[:final]
                if f && !f.to_s.empty?
                  final_text = f.to_s
                  break
                end
              end
            end
          end
        rescue StandardError
        end
        {
          id: (d['run_id'] || d[:run_id]).to_i,
          input: d['input'] || d[:input],
          output_summary: d['output_summary'] || d[:output_summary],
          status: d['status'] || d[:status],
          duration_ms: (d['duration_ms'] || d[:duration_ms]).to_i,
          created_at: (d['created_at'] || d[:created_at]).is_a?(Time) ? (d['created_at'] || d[:created_at]).iso8601 : d['created_at'] || d[:created_at],
          steps: steps_count,
          final: (d['output_summary'] && !d['output_summary'].to_s.empty?) ? d['output_summary'] : final_text
        }
      end
    end
  end
end
