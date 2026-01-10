#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'time'
require 'securerandom'
require_relative '../../framework/db'
require_relative '../../reasoning/client'
require_relative '../personas/ops'
require_relative '../drivers/ops'
require_relative '../rules/ops'

module Savant
  module Council
    # Council Role definitions with system prompts
    COUNCIL_ROLES = {
      'analyst' => {
        name: 'Analyst',
        description: 'Decomposes problems and proposes options with pros/cons',
        system_prompt: <<~PROMPT
          You are the Analyst role in an AI Council. Your responsibilities:
          - Decompose the problem into clear components
          - Identify and list all viable options
          - For each option, provide pros, cons, and underlying assumptions
          - Be thorough but concise
          - Focus on factual analysis, not opinions

          Output your analysis in this JSON format:
          {
            "problem_decomposition": ["component1", "component2"],
            "options": [
              {"name": "Option A", "pros": [], "cons": [], "assumptions": []}
            ],
            "recommendation": "Your recommended option",
            "confidence": 0.0-1.0,
            "reasoning": "Brief explanation"
          }
        PROMPT
      },
      'skeptic' => {
        name: 'Skeptic',
        description: 'Identifies risks, hidden assumptions, and challenges overconfidence',
        system_prompt: <<~PROMPT
          You are the Skeptic role in an AI Council. Your responsibilities:
          - Identify risks and potential failure modes
          - Surface hidden assumptions that others may have missed
          - Challenge overconfident claims with evidence-based skepticism
          - Ask probing questions that expose weaknesses
          - Play devil's advocate constructively

          Output your analysis in this JSON format:
          {
            "risks": [{"risk": "description", "severity": "low|medium|high|critical", "mitigation": "suggestion"}],
            "hidden_assumptions": ["assumption1", "assumption2"],
            "challenges": ["challenge1", "challenge2"],
            "questions": ["question1", "question2"],
            "overall_concern_level": "low|medium|high",
            "reasoning": "Brief explanation of your skepticism"
          }
        PROMPT
      },
      'pragmatist' => {
        name: 'Pragmatist',
        description: 'Optimizes for feasibility and proposes realistic paths',
        system_prompt: <<~PROMPT
          You are the Pragmatist role in an AI Council. Your responsibilities:
          - Evaluate feasibility of proposed options
          - Consider resource constraints, timelines, and practical limitations
          - Propose the most realistic default path forward
          - Identify quick wins and incremental improvements
          - Balance ideal solutions with practical realities

          Output your analysis in this JSON format:
          {
            "feasibility_assessment": [{"option": "name", "feasibility": "low|medium|high", "blockers": [], "enablers": []}],
            "recommended_path": "Your recommended practical approach",
            "quick_wins": ["win1", "win2"],
            "timeline_estimate": "rough estimate",
            "resource_requirements": ["requirement1", "requirement2"],
            "reasoning": "Brief explanation of your pragmatic assessment"
          }
        PROMPT
      },
      'safety' => {
        name: 'Safety/Ethics',
        description: 'Evaluates safety, compliance, and ethical considerations. Has VETO authority.',
        system_prompt: <<~PROMPT
          You are the Safety/Ethics role in an AI Council. You have VETO AUTHORITY.

          Your responsibilities:
          - Evaluate safety implications of all proposals
          - Check for compliance with relevant regulations and policies
          - Identify ethical concerns and potential harms
          - Assess impact on stakeholders
          - Exercise VETO if there are critical safety/ethical violations

          VETO CRITERIA (use sparingly, only for critical issues):
          - Clear violation of laws or regulations
          - Significant risk of harm to users or stakeholders
          - Fundamental ethical violations
          - Security vulnerabilities with high impact

          Output your analysis in this JSON format:
          {
            "safety_concerns": [{"concern": "description", "severity": "low|medium|high|critical"}],
            "compliance_issues": ["issue1", "issue2"],
            "ethical_considerations": ["consideration1", "consideration2"],
            "stakeholder_impacts": [{"stakeholder": "name", "impact": "description", "sentiment": "positive|neutral|negative"}],
            "veto": false,
            "veto_reason": null,
            "approval_conditions": ["condition1", "condition2"],
            "reasoning": "Brief explanation of your safety assessment"
          }
        PROMPT
      },
      'moderator' => {
        name: 'Moderator',
        description: 'Orchestrates the protocol and synthesizes the final answer',
        system_prompt: <<~PROMPT
          You are the Moderator role in an AI Council. Your responsibilities:
          - Synthesize inputs from all council members
          - Respect any VETO decisions from Safety/Ethics
          - Resolve conflicts between different perspectives
          - Produce a clear, actionable final recommendation
          - Ensure the decision is well-justified and complete

          You must produce a final synthesis that:
          1. Acknowledges key points from each role
          2. Explains how conflicts were resolved
          3. Provides a clear recommendation
          4. Lists next steps and action items

          Output your synthesis in this JSON format:
          {
            "summary": "Executive summary of the decision",
            "key_insights": {"analyst": "summary", "skeptic": "summary", "pragmatist": "summary", "safety": "summary"},
            "conflicts_resolved": [{"conflict": "description", "resolution": "how resolved"}],
            "final_recommendation": "The council's recommendation",
            "confidence": 0.0-1.0,
            "next_steps": ["step1", "step2"],
            "vetoed": false,
            "veto_explanation": null,
            "councilProtocolVersion": "1.0"
          }
        PROMPT
      }
    }.freeze

    class Ops
      PROTOCOL_VERSION = '1.0'

      def initialize(db: nil)
        @db = db || Savant::Framework::DB.new
        ensure_council_protocol_schema!
      end

      # Ensure council protocol schema extensions exist
      def ensure_council_protocol_schema!
        return if @protocol_schema_initialized

        @db.ensure_council_schema!
        # Add mode column if missing
        begin
          @db.exec("ALTER TABLE council_sessions ADD COLUMN IF NOT EXISTS mode TEXT DEFAULT 'chat'")
          @db.exec('ALTER TABLE council_sessions ADD COLUMN IF NOT EXISTS context JSONB')
          @db.exec('ALTER TABLE council_sessions ADD COLUMN IF NOT EXISTS artifacts JSONB')
        rescue StandardError
          # Column may already exist
        end
        # Create council_runs table for tracking council protocol executions
        @db.exec(<<~SQL)
          CREATE TABLE IF NOT EXISTS council_runs (
            id SERIAL PRIMARY KEY,
            session_id INTEGER NOT NULL REFERENCES council_sessions(id) ON DELETE CASCADE,
            run_id TEXT NOT NULL UNIQUE,
            status TEXT NOT NULL DEFAULT 'pending',
            phase TEXT,
            query TEXT,
            context JSONB,
            positions JSONB,
            debate_rounds JSONB,
            synthesis JSONB,
            votes JSONB,
            veto BOOLEAN DEFAULT FALSE,
            veto_reason TEXT,
            started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            completed_at TIMESTAMPTZ,
            error TEXT
          );
        SQL
        @db.exec('CREATE INDEX IF NOT EXISTS idx_council_runs_session ON council_runs(session_id)')
        @db.exec('CREATE INDEX IF NOT EXISTS idx_council_runs_status ON council_runs(status)')
        @protocol_schema_initialized = true
      rescue StandardError
        # best-effort
      end

      # Mongo helpers (best-effort)
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
        return @mongo_client if defined?(@mongo_client) && @mongo_client

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

      def sessions_col
        c = mongo_client
        c ? c[:council_sessions] : nil
      end

      def messages_col
        c = mongo_client
        c ? c[:council_messages] : nil
      end

      # Blackboard collections (shared with Rails app)
      def blackboard_sessions_col
        c = mongo_client
        c ? c[:blackboard_sessions] : nil
      end

      def blackboard_events_col
        c = mongo_client
        c ? c[:blackboard_events] : nil
      end

      def blackboard_sid_for(council_session_id)
        "council-#{council_session_id}"
      end

      # Ensure a Blackboard session exists for a given council session id.
      # Best-effort: ignore errors to avoid impacting chat.
      def ensure_blackboard_session_for(council_session_id:, title: nil, description: nil, user_id: nil, agents: [])
        return unless (bcol = blackboard_sessions_col)

        bb_sid = blackboard_sid_for(council_session_id)
        doc = bcol.find({ session_id: bb_sid }).limit(1).first
        now = Time.now.utc
        if doc
          # Reactivate/update an existing session if not active
          if (doc['state'] != 'active') || (doc['actors'].is_a?(Array) && !doc['actors'].include?(user_id))
            actors = (doc['actors'].is_a?(Array) ? doc['actors'] : [])
            actors << user_id.to_s if user_id && !user_id.to_s.empty? && !actors.include?(user_id.to_s)
            bcol.update_one({ session_id: bb_sid }, {
                              '$set' => {
                                state: 'active',
                                actors: actors.compact.uniq,
                                'metadata.title' => title || doc.dig('metadata', 'title'),
                                'metadata.description' => description || doc.dig('metadata', 'description'),
                                updated_at: now
                              }
                            })
          end
          return
        end
        # Create a fresh session document if missing
        actors = []
        actors << user_id.to_s if user_id && !user_id.to_s.empty?
        actors.concat(Array(agents).map(&:to_s))
        payload = {
          session_id: bb_sid,
          type: 'chat',
          actors: actors.compact.uniq,
          state: 'active',
          metadata: { source: 'council', council_session_id: council_session_id, title: title, description: description },
          created_at: now,
          updated_at: now
        }
        bcol.insert_one(payload)
        if (be = blackboard_events_col)
          be.insert_one({
                          event_id: SecureRandom.uuid,
                          session_id: bb_sid,
                          type: 'session_created',
                          actor_id: (user_id || 'system').to_s,
                          actor_type: user_id ? 'human' : 'system',
                          visibility: 'public',
                          payload: { title: title, description: description, agents: Array(agents).map(&:to_s) },
                          created_at: now,
                          updated_at: now,
                          version: 1
                        })
        end
      rescue StandardError
        # ignore
      end

      def insert_blackboard_event_for(council_session_id:, type:, actor_id:, actor_type:, payload: {})
        return unless (be = blackboard_events_col)

        now = Time.now.utc
        be.insert_one({
                        event_id: SecureRandom.uuid,
                        session_id: blackboard_sid_for(council_session_id),
                        type: type.to_s,
                        actor_id: (actor_id || 'system').to_s,
                        actor_type: (actor_type || 'system').to_s,
                        visibility: 'public',
                        payload: payload || {},
                        created_at: now,
                        updated_at: now,
                        version: 1
                      })
      rescue StandardError
        # ignore
      end

      # API
      def session_create(title: nil, agents: [], user_id: nil, description: nil)
        id = @db.create_council_session(title: title, user_id: user_id, agents: Array(agents).map(&:to_s), description: description)
        begin
          if (col = sessions_col)
            col.insert_one({ session_id: id, title: title, agents: Array(agents).map(&:to_s), description: description, user_id: user_id, created_at: Time.now.utc })
          end
          # Best-effort: mirror into Blackboard as a chat session for diagnostics/explorer
          if (bcol = blackboard_sessions_col)
            bb_sid = "council-#{id}"
            now = Time.now.utc
            actors = []
            actors << user_id.to_s if user_id && !user_id.to_s.empty?
            actors.concat(Array(agents).map(&:to_s))
            doc = {
              session_id: bb_sid,
              type: 'chat',
              actors: actors.compact.uniq,
              state: 'active',
              metadata: { source: 'council', council_session_id: id, title: title, description: description },
              created_at: now,
              updated_at: now
            }
            bcol.insert_one(doc)
            # Emit a creation event into blackboard_events for visibility
            if (be = blackboard_events_col)
              be.insert_one({
                              event_id: SecureRandom.uuid,
                              session_id: bb_sid,
                              type: 'session_created',
                              actor_id: (user_id || 'system').to_s,
                              actor_type: user_id ? 'human' : 'system',
                              visibility: 'public',
                              payload: { title: title, description: description, agents: Array(agents).map(&:to_s) },
                              created_at: now,
                              updated_at: now,
                              version: 1
                            })
            end
          end
        rescue StandardError
        end
        { id: id, title: title, description: description, agents: agents }
      end

      def sessions_list(limit: 50)
        rows = @db.list_council_sessions(limit: limit)
        rows.map do |r|
          preview = nil
          last_at = nil
          last_role = nil
          last_agent = nil
          begin
            m = @db.exec_params('SELECT role, agent_name, text, created_at FROM council_messages WHERE session_id=$1 ORDER BY id DESC LIMIT 1', [r['id'].to_i])
            if m.ntuples > 0
              row = m[0]
              last_role = row['role']
              last_agent = row['agent_name']
              body = (row['text'] || '').to_s
              snippet = body.length > 120 ? body[0, 120] + '…' : body
              if last_role == 'user'
                preview = "You: #{snippet}"
              else
                who = last_agent || 'Agent'
                preview = "#{who}: #{snippet}"
              end
              last_at = row['created_at']
            end
          rescue StandardError
          end
          {
            id: r['id'].to_i,
            title: r['title'],
            user_id: r['user_id'],
            agents: parse_text_array(r['agents']),
            description: r['description'],
            mode: r['mode'] || 'chat',
            created_at: r['created_at'],
            updated_at: r['updated_at'],
            last_preview: preview,
            last_at: last_at,
            last_role: last_role,
            last_agent_name: last_agent
          }
        end
      end

      def session_get(id:)
        data = @db.get_council_session(id)
        raise 'not_found' unless data

        sess = data[:session]
        msgs = data[:messages]
        # Get current council run if any
        council_run = current_council_run(id)
        {
          id: sess['id'].to_i,
          title: sess['title'],
          user_id: sess['user_id'],
          agents: parse_text_array(sess['agents']),
          description: sess['description'],
          mode: sess['mode'] || 'chat',
          context: safe_json_parse(sess['context']),
          artifacts: safe_json_parse(sess['artifacts']),
          created_at: sess['created_at'],
          updated_at: sess['updated_at'],
          messages: msgs.map { |m| normalize_msg(m) },
          council_run: council_run
        }
      end

      def session_update(id:, title: nil, agents: nil, description: nil)
        @db.update_council_session(id: id, title: title, agents: agents)
        @db.update_council_description(id: id, description: description) unless description.nil?
        session_get(id: id)
      end

      def append_user(session_id:, text:, user_id: nil)
        @db.add_council_message(session_id: session_id, role: 'user', text: text)
        begin
          if (col = messages_col)
            col.insert_one({ session_id: session_id.to_i, role: 'user', text: text.to_s, created_at: Time.now.utc, user_id: user_id })
          end
          # Ensure Blackboard session exists and emit a message event
          begin
            sess = @db.get_council_session(session_id)
            ensure_blackboard_session_for(
              council_session_id: session_id,
              title: sess && sess[:session] && sess[:session]['title'],
              description: sess && sess[:session] && sess[:session]['description'],
              user_id: user_id,
              agents: (sess && sess[:session] && sess[:session]['agents'] ? parse_text_array(sess[:session]['agents']) : [])
            )
          rescue StandardError
          end
          insert_blackboard_event_for(
            council_session_id: session_id,
            type: 'message_posted',
            actor_id: user_id || 'user',
            actor_type: 'human',
            payload: { text: text.to_s }
          )
        rescue StandardError
        end

        # Trigger reactions from all agents in the "room"
        begin
          trigger_agent_reactions(session_id: session_id, trigger_message_text: text, trigger_actor: user_id || 'User')
        rescue StandardError
        end

        # Optional: auto-run one reasoning step for this user input
        begin
          if env_truthy(ENV['COUNCIL_AUTO_AGENT_STEP'])
            agent_name = begin
              sess = @db.get_council_session(session_id)
              arr = sess && sess[:session] && sess[:session]['agents'] ? parse_text_array(sess[:session]['agents']) : []
              arr.is_a?(Array) && arr.first ? arr.first.to_s : 'agent'
            rescue StandardError
              'agent'
            end
            agent_step(session_id: session_id, goal_text: text.to_s, agent_name: agent_name)
          end
        rescue StandardError
        end

        { ok: true }
      end

      def append_agent(session_id:, agent_name:, run_id: nil, text: nil, status: 'ok', correlation_id: nil, job_id: nil, run_key: nil)
        # Sanitize echoed prompts
        display_text = text.to_s
        if is_echo?(display_text)
          display_text = '🤷'
        else
          begin
            # If it's a JSON payload, check the final_text field
            parsed = JSON.parse(display_text)
            if parsed.is_a?(Hash) && is_echo?(parsed['final_text'])
              parsed['final_text'] = '🤷'
              display_text = JSON.generate(parsed)
            end
          rescue StandardError
          end
        end

        @db.add_council_message(
          session_id: session_id,
          role: 'agent',
          agent_name: agent_name,
          run_id: run_id,
          text: display_text,
          status: status,
          correlation_id: correlation_id,
          job_id: job_id,
          run_key: run_key
        )
        begin
          if (col = messages_col)
            col.insert_one({
                             session_id: session_id.to_i,
                             role: 'agent',
                             agent_name: agent_name.to_s,
                             run_id: run_id,
                             status: status.to_s,
                             correlation_id: correlation_id,
                             job_id: job_id,
                             run_key: run_key,
                             text: text.to_s,
                             created_at: Time.now.utc
                           })
          end
          # Ensure Blackboard session exists and emit an agent reply event.
          unless status.to_s.strip.downcase == 'pending'
            begin
              sess = @db.get_council_session(session_id)
              ensure_blackboard_session_for(
                council_session_id: session_id,
                title: sess && sess[:session] && sess[:session]['title'],
                description: sess && sess[:session] && sess[:session]['description'],
                user_id: sess && sess[:session] && sess[:session]['user_id'],
                agents: (sess && sess[:session] && sess[:session]['agents'] ? parse_text_array(sess[:session]['agents']) : [])
              )
            rescue StandardError
            end
            insert_blackboard_event_for(
              council_session_id: session_id,
              type: 'agent_reply',
              actor_id: agent_name.to_s,
              actor_type: 'agent',
              payload: { text: text.to_s, status: status.to_s, run_id: run_id, correlation_id: correlation_id, job_id: job_id }
            )
          end
        rescue StandardError
        end

        # Trigger reactions if this wasn't a reaction itself
        unless run_key == 'reaction' || status.to_s.strip.downcase == 'pending'
          begin
            trigger_agent_reactions(session_id: session_id, trigger_message_text: text, trigger_actor: agent_name)
          rescue StandardError
          end
        end

        { ok: true }
      end

      # Perform a single reasoning step for this session by delegating to the Reasoning Worker (Redis transport).
      # Appends the result to Council messages as a structured JSON payload (in text) for easy UI rendering.
      def agent_step(session_id:, goal_text:, agent_name: nil)
        client = council_reasoning_client
        raise 'reasoning_unavailable' unless client.available?

        callback_url = council_reasoning_callback_url
        use_async = council_intent_async?
        payload = build_agent_payload(goal_text: goal_text.to_s, agent_name: agent_name, session_id: session_id)
        payload[:goal_text] = enrich_conversation_history(session_id, goal_text)
        # Include Blackboard session reference for workers
        begin
          payload[:blackboard_session_id] = blackboard_sid_for(session_id)
        rescue StandardError
          # ignore
        end
        if use_async && callback_url
          correlation_id = payload[:correlation_id].to_s
          # Record pending state in DB only; do not emit Blackboard pending events
          begin
            append_agent(
              session_id: session_id,
              agent_name: agent_name || 'agent',
              run_id: nil,
              text: JSON.generate({ schema: 'council.v1.agent_intent', type: 'agent_intent', action: 'pending', status: 'accepted', correlation_id: correlation_id }),
              status: 'pending',
              correlation_id: correlation_id
            )
          rescue StandardError
          end
          begin
            res = client.agent_intent_async(payload, callback_url: callback_url)
            @db.update_council_message_by_correlation_id(
              correlation_id: correlation_id,
              job_id: res[:job_id]
            )
            return { status: res[:status] || 'accepted', job_id: res[:job_id], correlation_id: correlation_id }
          rescue StandardError => e
            err = { schema: 'council.v1.agent_intent', type: 'error', error: e.message.to_s }
            @db.update_council_message_by_correlation_id(
              correlation_id: correlation_id,
              text: JSON.generate(err),
              status: 'error'
            )
            return { status: 'error', error: e.message.to_s, correlation_id: correlation_id }
          end
        end

        intent = client.agent_intent(payload)
        if intent.tool_name && !intent.tool_name.to_s.empty? && !tool_allowed?(intent.tool_name, payload)
          fallback = intent.final_text.to_s
          fallback = intent.reasoning.to_s if fallback.empty?
          fallback = 'Provide a direct answer.' if fallback.empty?
          intent = Savant::Reasoning::Intent.new(
            intent_id: intent.intent_id,
            tool_name: nil,
            tool_args: {},
            finish: true,
            final_text: fallback,
            reasoning: 'tools_disabled',
            trace: intent.trace
          )
        end
        action = if intent.finish
                   'finish'
                 elsif intent.tool_name && !intent.tool_name.to_s.empty?
                   'tool'
                 else
                   'reason'
                 end

        message = {
          schema: 'council.v1.agent_intent',
          type: 'agent_intent',
          action: action,
          finish: intent.finish ? true : false,
          intent_id: intent.intent_id,
          tool_name: intent.tool_name,
          tool_args: intent.tool_args || {},
          final_text: intent.final_text,
          reasoning: intent.reasoning,
          trace: intent.trace
        }
        append_agent(
          session_id: session_id,
          agent_name: agent_name || 'agent',
          run_id: nil,
          text: JSON.generate(message),
          status: intent.finish ? 'done' : 'pending'
        )
        # Blackboard: enrich timeline with reasoning/tool/results
        begin
          # Always record reasoning summary if present
          if intent.reasoning && !intent.reasoning.to_s.empty?
            insert_blackboard_event_for(
              council_session_id: session_id,
              type: 'agent_reasoning',
              actor_id: agent_name || 'agent',
              actor_type: 'agent',
              payload: { reasoning: intent.reasoning.to_s, trace_len: (intent.trace || []).length }
            )
          end
          # Tool suggested/requested
          if action == 'tool' && intent.tool_name && !intent.tool_name.to_s.empty?
            insert_blackboard_event_for(
              council_session_id: session_id,
              type: 'tool_call_requested',
              actor_id: agent_name || 'agent',
              actor_type: 'agent',
              payload: { tool_name: intent.tool_name, tool_args: intent.tool_args || {} }
            )
          end
          # Final result emitted
          if intent.finish && intent.final_text && !intent.final_text.to_s.empty?
            insert_blackboard_event_for(
              council_session_id: session_id,
              type: 'result_emitted',
              actor_id: agent_name || 'agent',
              actor_type: 'agent',
              payload: { text: intent.final_text.to_s }
            )
          end
        rescue StandardError
        end
        { status: 'ok' }.merge(message)
      rescue StandardError => e
        err = { schema: 'council.v1.agent_intent', type: 'error', error: e.message.to_s }
        begin
          append_agent(session_id: session_id, agent_name: agent_name || 'agent', run_id: nil, text: JSON.generate(err), status: 'error')
        rescue StandardError
        end
        { status: 'error', error: e.message }
      end

      def session_delete(id:)
        # Best-effort: cancel any in-flight reasoning jobs associated with this session's Blackboard ID
        begin
          bb_sid = blackboard_sid_for(id.to_i)
          begin
            require 'redis'
            r = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
            running = r.smembers('savant:jobs:running') || []
            running.each do |jid|
              meta_json = r.get("savant:job:meta:#{jid}")
              next unless meta_json && !meta_json.empty?

              begin
                meta = JSON.parse(meta_json)
                payload = meta.is_a?(Hash) ? (meta['payload'] || {}) : {}
                r.sadd('savant:jobs:cancel:requested', jid) if payload.is_a?(Hash) && payload['blackboard_session_id'].to_s == bb_sid
              rescue StandardError
              end
            end
          rescue StandardError
          ensure
            begin
              r&.close
            rescue StandardError
            end
          end
        rescue StandardError
        end
        # Simple delete: rely on FK cascade for messages
        @db.exec_params('DELETE FROM council_sessions WHERE id=$1', [id.to_i])
        begin
          if (col = sessions_col)
            col.delete_many({ session_id: id.to_i })
          end
          if (col2 = messages_col)
            col2.delete_many({ session_id: id.to_i })
          end
          # Kill (complete) the corresponding Blackboard session instead of deleting it
          bb_sid = blackboard_sid_for(id.to_i)
          now = Time.now.utc
          if (bcol = blackboard_sessions_col)
            bcol.update_one({ session_id: bb_sid }, { '$set' => { state: 'completed', updated_at: now } })
          end
          if (be = blackboard_events_col)
            be.insert_one({
                            event_id: SecureRandom.uuid,
                            session_id: bb_sid,
                            type: 'session_killed',
                            actor_id: 'System',
                            actor_type: 'system',
                            visibility: 'public',
                            payload: { reason: 'council_deleted', at: now.iso8601 },
                            created_at: now,
                            updated_at: now,
                            version: 1
                          })
          end
        rescue StandardError
        end
        { ok: true }
      end

      def session_clear(id:)
        mode = session_mode(session_id: id)
        raise 'session_in_council_mode' if mode == 'council'

        @db.clear_council_messages(session_id: id)
        @db.exec_params('DELETE FROM council_runs WHERE session_id=$1', [id.to_i])
        @db.exec_params('UPDATE council_sessions SET mode=$1, context=NULL, artifacts=NULL, updated_at=NOW() WHERE id=$2', ['chat', id.to_i])
        begin
          if (col = messages_col)
            col.delete_many({ session_id: id.to_i })
          end
          # Clear Blackboard events for this session, keep session doc
          if (be = blackboard_events_col)
            be.delete_many({ session_id: blackboard_sid_for(id.to_i) })
          end
          # Emit session_cleared marker for history trails
          begin
            insert_blackboard_event_for(
              council_session_id: id.to_i,
              type: 'session_cleared',
              actor_id: 'System',
              actor_type: 'system',
              payload: {}
            )
          rescue StandardError
          end
        rescue StandardError
        end
        { ok: true }
      end

      # Delete a single Blackboard event (and corresponding council_messages row where possible).
      # scope: 'single' (default) deletes just that event; 'turn' deletes from a user message until the next user message.
      def delete_message_event(session_id:, event_id:, scope: 'single')
        be = blackboard_events_col
        raise 'blackboard_unavailable' unless be

        ev = be.find({ event_id: event_id.to_s }).limit(1).first
        raise 'event_not_found' unless ev

        bb_sid = blackboard_sid_for(session_id)
        deleted_events = 0
        deleted_pg = 0
        # Normalize created_at as Time
        ev_created_at = begin
          t = ev['created_at'] || ev[:created_at]
          t.is_a?(Time) ? t : Time.parse(t.to_s)
        rescue StandardError
          Time.now.utc
        end

        if scope.to_s == 'turn'
          # Determine time window from this user message to next user message
          # If the event is not a user message, we still use its created_at as start
          start_at = ev_created_at
          nxt = be.find({ session_id: bb_sid, type: 'message_posted', :created_at => { '$gt' => start_at } }).sort({ created_at: 1 }).limit(1).first rescue nil
          end_at = begin
            if nxt
              t = nxt['created_at'] || nxt[:created_at]
              t.is_a?(Time) ? t : Time.parse(t.to_s)
            else
              Time.now.utc + 1 # exclusive upper bound
            end
          rescue StandardError
            Time.now.utc + 1
          end
          # Delete Blackboard events in this window
          begin
            res = be.delete_many({ session_id: bb_sid, :created_at => { '$gte' => start_at, '$lt' => end_at } })
            deleted_events += (res.respond_to?(:deleted_count) ? res.deleted_count : 0)
          rescue StandardError
            # ignore
          end
          # Delete PG messages in the same window
          begin
            @db.delete_council_messages_in_time_range(session_id: session_id, start_time: start_at, end_time: end_at)
            # We can't easily retrieve count without extra query
          rescue StandardError
            # ignore
          end
          return { ok: true, deleted_events: deleted_events, scope: 'turn' }
        end

        # scope == 'single'
        begin
          res = be.delete_one({ event_id: event_id.to_s })
          deleted_events += (res.respond_to?(:deleted_count) ? res.deleted_count : 0)
        rescue StandardError
          # ignore
        end

        # Best-effort: delete a matching council_messages row
        begin
          type = (ev['type'] || ev[:type]).to_s
          payload = (ev['payload'] || ev[:payload] || {})
          if type == 'message_posted'
            # Match by exact text and time proximity
            text = (payload['text'] || payload[:text] || '').to_s
            if text && !text.empty?
              mid = @db.find_user_message_id_by_text_near(session_id: session_id, text: text, around_time: ev_created_at)
              @db.delete_council_message_by_id(mid) if mid
            end
          elsif type == 'agent_reply'
            agent_name = (ev['actor_id'] || ev[:actor_id] || 'agent').to_s
            corr = payload['correlation_id'] || payload[:correlation_id]
            job = payload['job_id'] || payload[:job_id]
            rid = payload['run_id'] || payload[:run_id]
            text = payload['text'] || payload[:text]
            mid = @db.find_agent_message_id(
              session_id: session_id,
              agent_name: agent_name,
              correlation_id: corr,
              job_id: job,
              run_id: rid,
              text: text,
              around_time: ev_created_at
            )
            @db.delete_council_message_by_id(mid) if mid
          end
        rescue StandardError
          # ignore
        end

        { ok: true, deleted_events: deleted_events }
      end

      # =========================
      # Council Protocol Methods
      # =========================

      # Get available council roles
      def council_roles
        COUNCIL_ROLES.map do |key, role|
          { id: key, name: role[:name], description: role[:description] }
        end
      end

      # Get current session mode (chat or council)
      def session_mode(session_id:)
        res = @db.exec_params('SELECT mode FROM council_sessions WHERE id=$1', [session_id.to_i])
        return 'chat' if res.ntuples.zero?

        res[0]['mode'] || 'chat'
      end

      # Set session mode
      def set_session_mode(session_id:, mode:)
        valid_modes = %w[chat council]
        mode = 'chat' unless valid_modes.include?(mode.to_s)
        @db.exec_params('UPDATE council_sessions SET mode=$1, updated_at=NOW() WHERE id=$2', [mode, session_id.to_i])
        { ok: true, mode: mode }
      end

      # Get the current/latest council run for a session
      def current_council_run(session_id)
        res = @db.exec_params(
          'SELECT * FROM council_runs WHERE session_id=$1 ORDER BY id DESC LIMIT 1',
          [session_id.to_i]
        )
        return nil if res.ntuples.zero?

        normalize_council_run(res[0])
      end

      # Get a specific council run by run_id
      def get_council_run(run_id:)
        res = @db.exec_params('SELECT * FROM council_runs WHERE run_id=$1', [run_id.to_s])
        return nil if res.ntuples.zero?

        normalize_council_run(res[0])
      end

      # List all council runs for a session
      def list_council_runs(session_id:, limit: 20)
        res = @db.exec_params(
          'SELECT * FROM council_runs WHERE session_id=$1 ORDER BY id DESC LIMIT $2',
          [session_id.to_i, limit.to_i]
        )
        res.to_a.map { |r| normalize_council_run(r) }
      end

      # Escalate from chat to council mode
      # This freezes the current conversation context and prepares for council deliberation
      def escalate_to_council(session_id:, query: nil, user_id: nil)
        session = session_get(id: session_id)
        raise 'session_not_found' unless session

        # Require at least 2 agents for council deliberation
        agents = session[:agents] || []
        raise 'insufficient_agents: Council deliberation requires at least 2 agents' if agents.length < 2

        # Build conversation context from messages - include FULL history
        messages = session[:messages] || []
        full_chat_history = build_full_chat_history(messages)
        conversation_summary = summarize_conversation(messages)

        # Extract constraints and options from the conversation
        context = {
          full_chat_history: full_chat_history,
          conversation_summary: conversation_summary,
          constraints: extract_constraints(messages),
          options: extract_options(messages),
          original_query: query || extract_original_query(messages)
        }

        # Create a new council run
        run_id = "council-#{session_id}-#{SecureRandom.hex(8)}"
        @db.exec_params(
          <<~SQL, [session_id.to_i, run_id, 'pending', 'init', query, JSON.generate(context)]
            INSERT INTO council_runs(session_id, run_id, status, phase, query, context)
            VALUES($1, $2, $3, $4, $5, $6)
          SQL
        )

        # Update session mode
        set_session_mode(session_id: session_id, mode: 'council')

        # Blackboard: council started
        begin
          ensure_blackboard_session_for(
            council_session_id: session_id,
            title: session[:title],
            description: session[:description],
            user_id: session[:user_id],
            agents: session[:agents]
          )
          insert_blackboard_event_for(
            council_session_id: session_id,
            type: 'council_started',
            actor_id: user_id || 'system',
            actor_type: user_id ? 'human' : 'system',
            payload: { run_id: run_id, query: query || context[:original_query] }
          )
        rescue StandardError
        end

        # Add system message about council escalation
        append_agent(
          session_id: session_id,
          agent_name: 'System',
          run_id: run_id,
          run_key: run_id,
          text: "Council deliberation started. Query: #{query || context[:original_query]}",
          status: 'ok'
        )

        { ok: true, run_id: run_id, session_id: session_id, mode: 'council', context: context }
      end

      # Run the full council protocol
      # This executes all phases: Intent Classification → Initial Positions → Debate → Synthesis
      def run_council_protocol(session_id:, run_id: nil, max_debate_rounds: 3)
        # Get or create run
        run = if run_id
                get_council_run(run_id: run_id)
              else
                current_council_run(session_id)
              end
        raise 'no_council_run' unless run

        run_id = run[:run_id]
        update_run_status(run_id, 'running', 'positions')
        max_rounds = [max_debate_rounds.to_i, 3].min

        begin
          # Phase 1: Initial Positions (one per agent)
          positions = begin
            execute_initial_positions(run)
          rescue StandardError => e
            members = session_agents_for_run(run)
            members.map { |name| { agent: name, position: skipped_agent_payload(name, e) } }
          end
          update_run_positions(run_id, positions)

          update_run_status(run_id, 'running', 'debate')

          # Phase 2: Debate/Refinement (optional rounds)
          debate_rounds = []
          max_rounds.times do |round|
            debate_result = begin
              execute_debate_round(run, positions, round + 1, debate_rounds)
            rescue StandardError => e
              {
                round: round + 1,
                items: skipped_agents_for_debate(run, e),
                consensus: false,
                error: e.message.to_s
              }
            end
            debate_rounds << debate_result

            # Check if consensus reached
            break if debate_result[:consensus]
          end
          update_run_debate(run_id, debate_rounds)

          update_run_status(run_id, 'running', 'synthesis')

          # Phase 3: Synthesis (Moderator)
          synthesis = begin
            execute_synthesis(run, positions, debate_rounds)
          rescue StandardError => e
            fallback = generate_demo_synthesis(run, positions, debate_rounds)
            fallback['note'] = "Moderator skipped after retries: #{e.message}"
            fallback
          end
          skipped = positions.select do |p|
            pos = p[:position] || p['position']
            pos.is_a?(Hash) && pos['skipped']
          end.map { |p| p[:agent] || p['agent'] }
          synthesis['skipped_agents'] = skipped if skipped.any?
          update_run_synthesis(run_id, synthesis)

          # Store final recommendation message
          append_agent(
            session_id: session_id,
            agent_name: 'Moderator',
            text: JSON.generate({ type: 'synthesis', synthesis: synthesis }),
            status: 'ok',
            run_key: run_id
          )

          # Complete and return to chat
          update_run_status(run_id, 'completed', 'complete')
          return_to_chat(session_id: session_id, message: synthesis[:summary] || 'Council deliberation complete')

          {
            ok: true,
            run_id: run_id,
            status: 'completed',
            synthesis: synthesis,
            positions: positions,
            debate_rounds: debate_rounds
          }
        rescue StandardError => e
          update_run_error(run_id, e.message)
          return_to_chat(session_id: session_id, message: "Council error: #{e.message}")
          { ok: false, run_id: run_id, status: 'error', error: e.message }
        end
      end

      # Return from council mode to chat mode
      def return_to_chat(session_id:, message: nil)
        set_session_mode(session_id: session_id, mode: 'chat')

        # Blackboard: return to chat event
        begin
          insert_blackboard_event_for(
            council_session_id: session_id,
            type: 'return_to_chat',
            actor_id: 'System',
            actor_type: 'system',
            payload: { message: message }
          )
        rescue StandardError
        end

        if message
          append_agent(
            session_id: session_id,
            agent_name: 'System',
            text: "Returned to chat mode. #{message}",
            status: 'ok'
          )
        end

        { ok: true, mode: 'chat' }
      end

      # Get council status for a session
      def council_status(session_id:)
        session = session_get(id: session_id)
        run = current_council_run(session_id)
        {
          session_id: session_id,
          mode: session[:mode] || 'chat',
          council_run: run,
          roles: council_roles
        }
      end

      private

      # Check if demo mode is enabled (for testing without reasoning API)
      def demo_mode?
        %w[1 true].include?(ENV['COUNCIL_DEMO_MODE'])
      end

      # Execute initial positions for all agents in the council session
      def trigger_agent_reactions(session_id:, trigger_message_text:, trigger_actor:)
        return if env_falsy(ENV['COUNCIL_REACTIONS_ENABLED']) # Allow disabling if needed

        agents = begin
          sess = session_get(id: session_id)
          parse_text_array(sess[:session]['agents'])
        rescue StandardError
          []
        end

        # Don't react to yourself
        agents.reject! { |a| a.to_s.downcase == trigger_actor.to_s.downcase }
        return if agents.empty?

        Thread.new do
          agents.each do |agent_name|
            Thread.new do
              client = council_reasoning_client
              next unless client.available?

              # We use a specialized payload for reactions
              payload = build_agent_payload(goal_text: trigger_message_text, agent_name: agent_name, session_id: session_id)
              payload[:is_reaction] = true
              payload[:instructions] = "You are in REACTION MODE. Evaluate the last message from #{trigger_actor} and decide if you want to AGREE, DISAGREE, or IGNORE."
              payload[:goal_text] = enrich_conversation_history(session_id, trigger_message_text)

              intent = with_retries("reaction:#{agent_name}") do
                client.agent_intent(payload)
              end

              if intent.finish && intent.final_text && !intent.final_text.strip.empty?
                # Use a dedicated run_key to avoid recursive reactions
                append_agent(
                  session_id: session_id,
                  agent_name: agent_name,
                  text: intent.final_text,
                  status: 'ok',
                  correlation_id: "reaction-#{SecureRandom.hex(4)}",
                  run_key: 'reaction'
                )
              end
            rescue StandardError
              # Silent failure for reactions
            end
          end
        end
      end

      def enrich_conversation_history(session_id, goal_text)
        sess = session_get(id: session_id)
        msgs = Array(sess[:messages] || [])
        # Filter: keep only user and non-system agent messages
        filtered = msgs.select do |m|
          r = (m[:role] || '').to_s
          agent = (m[:agent_name] || '').to_s.downcase
          status = (m[:status] || '').to_s.downcase
          (r == 'user' || (r == 'agent' && agent != 'system')) && status != 'pending'
        end
        # The latest message is the one we are reacting to or answering
        # If we are in agent_step, the latest message is ALREADY in the DB if called after append_user.
        # However, enrich_conversation_history is called with goal_text.

        # Build chronological lines
        lines = filtered.map do |m|
          who = m[:role] == 'user' ? 'User' : (m[:agent_name] || 'Agent')
          txt = (m[:text] || '').to_s
          "#{who}: #{txt}"
        end

        # If the goal_text is already the last line of history, avoid duplication
        last_line = lines.last.to_s
        if last_line.include?(goal_text.to_s[0..20])
          # Already there
        else
          # Append it if it's new context
          # lines << "QUERY: #{goal_text}"
        end

        history = lines.join("\n")
        <<~PROMPT
          Conversation History:
          #{history}

          CURRENT CONTEXT: #{goal_text}

          Please provide your response based on the conversation above.
        PROMPT
      rescue StandardError
        goal_text
      end

      def is_echo?(text)
        return false if text.to_s.strip.empty?

        # Check for multiple prompt markers
        hits = 0
        hits += 1 if text.include?('Conversation History:')
        hits += 1 if text.include?('CURRENT CONTEXT:')
        hits += 1 if text.include?('CURRENT USER QUERY:')
        hits += 1 if text.include?('Please provide your response')
        hits >= 2
      end

      def env_falsy(val)
        return false if val.nil?

        %w[false 0 no off f].include?(val.to_s.downcase.strip)
      end

      def execute_initial_positions(run)
        # Use demo mode if reasoning API not available
        return generate_demo_positions(run) if demo_mode?

        client = council_reasoning_client
        unless client.available?
          # Fall back to demo mode if reasoning unavailable
          return generate_demo_positions(run)
        end

        members = session_agents_for_run(run)

        # Execute agents in parallel to avoid sequential timeout bottlenecks
        threads = members.map do |agent_name|
          Thread.new do
            prompt = build_agent_position_prompt(run, agent_name)
            begin
              result = with_retries("positions:#{agent_name}") do
                payload = build_agent_payload(goal_text: prompt, agent_name: agent_name, session_id: run[:session_id])
                client.agent_intent(payload)
              end
              { agent: agent_name, position: parse_agent_response(result, agent_name) }
            rescue StandardError => e
              { agent: agent_name, position: skipped_agent_payload(agent_name, e) }
            end
          end
        end

        threads.map(&:value)
      end

      # Generate demo positions without calling the reasoning API
      def generate_demo_positions(run)
        context = run[:context] || {}
        query = run[:query] || context['original_query'] || context[:original_query] || 'the proposed decision'
        chat_summary = context['conversation_summary'] || context[:conversation_summary] || ''

        # Extract key topics from the chat for more relevant responses
        topic_hint = chat_summary.to_s[0, 200] if chat_summary.present?
        topic_note = topic_hint ? " Based on conversation about: #{topic_hint}" : ''

        members = session_agents_for_run(run)
        members.map do |agent_name|
          {
            agent: agent_name,
            position: {
              query: query,
              summary: "Initial position from #{agent_name}.#{topic_note}",
              reasoning: "Based on: #{query}.#{topic_note}"
            }
          }
        end
      end

      # Execute a debate round
      def execute_debate_round(run, positions, round_number, prior_rounds = [])
        # Use demo mode if reasoning API not available
        return generate_demo_debate(run, positions, round_number) if demo_mode?

        client = council_reasoning_client
        return generate_demo_debate(run, positions, round_number) unless client.available?

        # Build summary of all positions for debate
        positions_summary = positions.map do |entry|
          agent = entry[:agent] || entry['agent'] || 'agent'
          pos = entry[:position] || entry['position'] || entry
          "#{agent}: #{JSON.generate(pos)}"
        end.join("\n\n")

        prior_summary = (prior_rounds || []).map do |round|
          items = round[:items] || round['items'] || []
          "Round #{round[:round] || round['round']}:\n#{JSON.generate(items)}"
        end.join("\n\n")

        members = session_agents_for_run(run)

        # Execute debate agents in parallel
        threads = members.map do |agent_name|
          Thread.new do
            debate_prompt = <<~PROMPT
              This is debate round #{round_number} of a maximum of 3. Review the positions from all council members and respond.

              Current positions:
              #{positions_summary}

              Previous rounds:
              #{prior_summary.presence || 'None'}

              Original query: #{run[:query]}

              Provide your feedback in this order:
              1. Your updated position based on the current information.
              2. Review other agents' responses and explicitly call out any contradictions or disagreements.
              3. If you disagree, argue your position briefly and propose a resolution. If you agree, say "no disagreements".

              Keep it concise. This process repeats for up to 3 rounds total.
            PROMPT

            begin
              result = with_retries("debate:#{round_number}:#{agent_name}") do
                payload = build_agent_payload(goal_text: debate_prompt, agent_name: agent_name, session_id: run[:session_id])
                client.agent_intent(payload)
              end
              { agent: agent_name, text: (result.final_text || result.reasoning || '').to_s }
            rescue StandardError => e
              { agent: agent_name, text: skipped_agent_payload(agent_name, e) }
            end
          end
        end

        items = threads.map(&:value)

        # Check for consensus
        consensus = check_consensus_from_items(items)

        { round: round_number, items: items, consensus: consensus }
      end

      # Generate demo debate without calling reasoning API
      def generate_demo_debate(_run, _positions, round_number)
        {
          round: round_number,
          items: [
            { agent: 'Agent A', text: 'Agree with main approach; no disagreements.' },
            { agent: 'Agent B', text: 'Minor concern about timeline; propose slight buffer.' }
          ],
          consensus: true
        }
      end

      # Execute synthesis by Moderator
      def execute_synthesis(run, positions, debate_rounds)
        # Use demo mode if reasoning API not available
        return generate_demo_synthesis(run, positions, debate_rounds) if demo_mode?

        client = council_reasoning_client
        return generate_demo_synthesis(run, positions, debate_rounds) unless client.available?

        role = COUNCIL_ROLES['moderator']

        # Build comprehensive summary for moderator
        positions_summary = positions.map do |entry|
          agent = entry[:agent] || entry['agent'] || 'agent'
          pos = entry[:position] || entry['position'] || entry
          "#{agent}:\n#{JSON.generate(pos)}"
        end.join("\n\n---\n\n")

        debate_summary = debate_rounds.map do |round|
          "Round #{round[:round]}:\n#{JSON.generate(round[:items] || [])}"
        end.join("\n\n")

        synthesis_prompt = <<~PROMPT
          You are the Moderator. Synthesize the council's deliberation into a final recommendation.

          Original Query: #{run[:query]}

          Initial Positions:
          #{positions_summary}

          Debate Rounds:
          #{debate_summary.empty? ? 'No debate rounds' : debate_summary}

          Produce a final synthesis that:
          1. Summarizes key insights from each agent
          2. Resolves conflicts between perspectives
          3. Picks the best answer and explains why
          4. Lists concrete next steps
        PROMPT

        begin
          result = with_retries('synthesis:moderator') do
            client.agent_intent({
                                  session_id: "council-#{run[:run_id]}-synthesis",
                                  persona: { name: 'council-moderator', system_prompt: role[:system_prompt] },
                                  goal_text: synthesis_prompt,
                                  correlation_id: "#{run[:run_id]}-synthesis"
                                })
          end

          synthesis = parse_role_response(result, 'moderator')
          synthesis[:councilProtocolVersion] = PROTOCOL_VERSION
          synthesis
        rescue StandardError => e
          fallback = generate_demo_synthesis(run, positions, debate_rounds)
          fallback['note'] = "Moderator skipped after retries: #{e.message}"
          fallback
        end
      end

      # Generate demo synthesis without calling reasoning API
      def generate_demo_synthesis(run, _positions, _debate_rounds)
        query = run[:query] || 'the proposed decision'
        {
          'summary' => "After deliberation on #{query}, the council recommends the clearest, most actionable answer based on the agents' feedback.",
          'key_insights' => [
            'Multiple perspectives considered',
            'Conflicts resolved where possible',
            'A single best answer chosen'
          ],
          'conflicts_resolved' => [
            { 'conflict' => 'Competing interpretations', 'resolution' => 'Chose the most consistent answer' }
          ],
          'final_recommendation' => "Best answer for: #{query}",
          'confidence' => 0.8,
          'next_steps' => [
            '1. Validate the chosen answer with stakeholders',
            '2. Document the final recommendation',
            '3. Execute the agreed next steps'
          ],
          'councilProtocolVersion' => PROTOCOL_VERSION
        }
      end

      def council_role_retries
        (ENV['COUNCIL_ROLE_RETRIES'] || '3').to_i
      end

      def council_role_timeout_ms
        (ENV['COUNCIL_ROLE_TIMEOUT_MS'] || '60000').to_i
      end

      def council_reasoning_client
        Savant::Reasoning::Client.new(timeout_ms: council_role_timeout_ms)
      end

      def skipped_role_payload(role_key, err)
        msg = err.is_a?(StandardError) ? err.message.to_s : err.to_s
        status = msg.downcase.include?('timeout') ? 'timeout' : 'error'
        {
          'role' => role_key,
          'skipped' => true,
          'status' => status,
          'error' => msg,
          'note' => 'Role skipped after retries'
        }
      end

      def skipped_roles_payload(label, err)
        payload = {}
        %w[analyst skeptic pragmatist safety].each do |role_key|
          payload[role_key] = skipped_role_payload(role_key, err)
        end
        payload['note'] = "Step skipped: #{label}"
        payload
      end

      def with_retries(label, retries: council_role_retries)
        attempts = 0
        begin
          attempts += 1
          yield
        rescue StandardError => e
          raise e if attempts > retries

          sleep(0.4 * attempts)
          retry
        end
      end

      # Build prompt for initial position
      def build_position_prompt(run, role)
        context = run[:context] || {}
        full_history = context['full_chat_history'] || context[:full_chat_history] || ''
        query = run[:query] || context['original_query'] || context[:original_query] || 'No specific query'

        <<~PROMPT
          You are participating in a council deliberation. Analyze the following conversation and provide your perspective.

          === COUNCIL QUERY ===
          #{query}

          === FULL CONVERSATION HISTORY ===
          #{full_history.presence || 'No prior conversation'}

          === YOUR TASK ===
          As the #{role[:name]}, analyze this conversation and the query. #{role[:description]}

          Provide your analysis in the JSON format specified in your system prompt.
        PROMPT
      end

      def build_agent_position_prompt(run, agent_name)
        context = run[:context] || {}
        summary = context['conversation_summary'] || context[:conversation_summary] || ''
        query = run[:query] || context['original_query'] || context[:original_query] || 'No specific query'
        <<~PROMPT
          You are #{agent_name}. Provide your position on the query below.

          Query:
          #{query}

          Conversation summary:
          #{summary.presence || 'No prior summary'}

          Give your concise position and any key reasoning.
        PROMPT
      end

      # Parse response from role
      def parse_role_response(result, role_key)
        text = result.final_text || result.reasoning || ''
        begin
          # Try to extract JSON from the response
          json_match = text.match(/\{[\s\S]*\}/)
          if json_match
            JSON.parse(json_match[0])
          else
            { role: role_key, response: text }
          end
        rescue JSON::ParserError
          { role: role_key, response: text }
        end
      end

      def parse_agent_response(result, agent_name)
        text = result.final_text || result.reasoning || ''
        begin
          json_match = text.match(/\{[\s\S]*\}/)
          if json_match
            JSON.parse(json_match[0])
          else
            { agent: agent_name, response: text }
          end
        rescue JSON::ParserError
          { agent: agent_name, response: text }
        end
      end

      def skipped_agent_payload(agent_name, err)
        base = skipped_role_payload(agent_name, err)
        base['agent'] = agent_name
        base
      end

      def skipped_agents_for_debate(run, err)
        members = session_agents_for_run(run)
        members.map { |name| { agent: name, text: skipped_agent_payload(name, err) } }
      end

      def check_consensus_from_items(items)
        return false unless items.is_a?(Array) && !items.empty?

        texts = items.map { |i| i[:text] || i['text'] || '' }.map(&:to_s)
        return false if texts.any?(&:empty?)

        texts.all? { |t| t.downcase.include?('no disagreements') || t.downcase.include?('agree') }
      end

      # Check if consensus has been reached
      def check_consensus(refinements)
        # Simple heuristic: check if all roles have low concern levels
        concerns = refinements.values.reject { |r| r.is_a?(Hash) && r['skipped'] }.map { |r| r['overall_concern_level'] || r['concern_level'] }.compact
        return true if concerns.empty?

        high_concerns = concerns.count { |c| %w[high critical].include?(c.to_s.downcase) }
        high_concerns.zero?
      end

      # Update helpers for council runs
      def update_run_status(run_id, status, phase)
        if status == 'completed'
          @db.exec_params(
            'UPDATE council_runs SET status=$1, phase=$2, completed_at=NOW() WHERE run_id=$3',
            [status, phase, run_id]
          )
        else
          @db.exec_params('UPDATE council_runs SET status=$1, phase=$2 WHERE run_id=$3', [status, phase, run_id])
        end
      end

      def update_run_positions(run_id, positions)
        @db.exec_params('UPDATE council_runs SET positions=$1 WHERE run_id=$2', [JSON.generate(positions), run_id])
      end

      def update_run_debate(run_id, debate_rounds)
        @db.exec_params('UPDATE council_runs SET debate_rounds=$1 WHERE run_id=$2', [JSON.generate(debate_rounds), run_id])
      end

      def update_run_synthesis(run_id, synthesis)
        @db.exec_params('UPDATE council_runs SET synthesis=$1 WHERE run_id=$2', [JSON.generate(synthesis), run_id])
      end

      def update_run_veto(run_id, veto, veto_reason)
        @db.exec_params('UPDATE council_runs SET veto=$1, veto_reason=$2 WHERE run_id=$3', [veto, veto_reason, run_id])
      end

      def update_run_error(run_id, error)
        @db.exec_params(
          'UPDATE council_runs SET status=$1, error=$2, completed_at=NOW() WHERE run_id=$3',
          ['error', error, run_id]
        )
      end

      # Normalize council run from DB row
      def normalize_council_run(row)
        {
          id: row['id'].to_i,
          session_id: row['session_id'].to_i,
          run_id: row['run_id'],
          status: row['status'],
          phase: row['phase'],
          query: row['query'],
          context: safe_json_parse(row['context']),
          positions: safe_json_parse(row['positions']),
          debate_rounds: safe_json_parse(row['debate_rounds']),
          synthesis: safe_json_parse(row['synthesis']),
          votes: safe_json_parse(row['votes']),
          veto: [true, 't'].include?(row['veto']),
          veto_reason: row['veto_reason'],
          started_at: row['started_at'],
          completed_at: row['completed_at'],
          error: row['error']
        }
      end

      # Conversation analysis helpers
      # Build full chat history without truncation for council context
      def build_full_chat_history(messages)
        return '' if messages.empty?

        # Filter system messages; keep only user and non-system agent messages
        filtered = messages.select do |m|
          r = (m[:role] || '').to_s
          agent = (m[:agent_name] || '').to_s.downcase
          r == 'user' || (r == 'agent' && agent != 'system')
        end
        total = filtered.size
        return '' if total.zero?

        # Build chronological history
        ordered = filtered.sort_by { |m| m[:created_at].to_s }
        lines = ordered.map do |m|
          role = m[:role] == 'user' ? 'User' : (m[:agent_name] || 'Agent')
          text = (m[:text] || '').to_s
          "#{role}: #{text}"
        end
        lines.join("\n")
      end

      def summarize_conversation(messages)
        return '' if messages.empty?

        filtered = messages.select do |m|
          r = (m[:role] || '').to_s
          agent = (m[:agent_name] || '').to_s.downcase
          r == 'user' || (r == 'agent' && agent != 'system')
        end
        return '' if filtered.empty?

        # Oldest -> newest, brief lines
        filtered.sort_by { |m| m[:created_at].to_s }.map do |m|
          role = m[:role] == 'user' ? 'User' : (m[:agent_name] || 'Agent')
          text = (m[:text] || '').to_s[0, 200]
          "#{role}: #{text}"
        end.join("\n")
      end

      def extract_constraints(messages)
        # Simple heuristic: look for constraint-like language
        constraints = []
        messages.each do |m|
          text = (m[:text] || '').to_s.downcase
          constraints << (m[:text] || '').to_s[0, 100] if text.include?('must') || text.include?('require') || text.include?('constraint')
        end
        constraints.uniq
      end

      def extract_options(messages)
        # Simple heuristic: look for option-like language
        options = []
        messages.each do |m|
          text = (m[:text] || '').to_s.downcase
          options << (m[:text] || '').to_s[0, 100] if text.include?('option') || text.include?('could') || text.include?('alternative')
        end
        options.uniq
      end

      def extract_original_query(messages)
        # Get the first user message as the original query
        user_msg = messages.find { |m| m[:role] == 'user' }
        user_msg ? (user_msg[:text] || '').to_s[0, 500] : 'No query specified'
      end

      def safe_json_parse(val)
        return nil if val.nil?
        return val if val.is_a?(Hash) || val.is_a?(Array)

        JSON.parse(val.to_s)
      rescue JSON::ParserError
        nil
      end

      def env_truthy(v)
        return false if v.nil?

        %w[1 true yes on].include?(v.to_s.strip.downcase)
      end

      def session_agents_for_run(run)
        sid = run[:session_id] || run['session_id']
        return [] unless sid

        data = @db.get_council_session(sid.to_i)
        return [] unless data && data[:session]

        parse_text_array(data[:session]['agents'])
      rescue StandardError
        []
      end

      def parse_text_array(val)
        # postgres text[] arrives as String like {a,b}
        return [] if val.nil?

        s = val.to_s
        return [] if s.empty?

        s = s.strip
        s = s[1..-2] if s.start_with?('{') && s.end_with?('}')
        return [] if s.empty?

        s.split(',')
      rescue StandardError
        []
      end

      def parse_int_array(val)
        return [] if val.nil?

        s = val.to_s
        return [] if s.empty?

        s = s.strip
        s = s[1..-2] if s.start_with?('{') && s.end_with?('}')
        return [] if s.empty?

        s.split(',').map(&:to_i)
      rescue StandardError
        []
      end

      def persona_name(row)
        pid = row['persona_id']
        return nil unless pid

        res = @db.exec_params('SELECT name FROM personas WHERE id=$1', [pid])
        res.ntuples.positive? ? res[0]['name'] : nil
      rescue StandardError
        nil
      end

      def build_agent_payload(goal_text:, agent_name:, session_id:)
        corr = "council-#{session_id}-#{Time.now.to_i}-#{SecureRandom.hex(3)}"
        row = nil
        begin
          row = @db.find_agent_by_name(agent_name.to_s) if agent_name
        rescue StandardError
          row = nil
        end
        return { session_id: "council-#{session_id}", persona: { name: 'savant-engineer' }, goal_text: goal_text, correlation_id: corr } unless row

        persona_data = nil
        begin
          pname = persona_name(row)
          persona_data = Savant::Personas::Ops.new.get(name: pname) if pname
        rescue StandardError
          persona_data = nil
        end

        driver_data = nil
        begin
          dname = row['driver_name'] || row['driver_prompt']
          driver_data = Savant::Drivers::Ops.new.get(name: dname) if dname && !dname.to_s.strip.empty?
        rescue StandardError
          driver_data = nil
        end

        rules_data = []
        begin
          rule_ids = parse_int_array(row['rule_set_ids'])
          unless rule_ids.empty?
            param = "{#{rule_ids.join(',')}}"
            res = @db.exec_params('SELECT id, name, version, summary, rules_md FROM rulesets WHERE id = ANY($1::int[]) ORDER BY name ASC', [param])
            rules_data = res.map do |r|
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
          rules_data = []
        end

        tools_list = parse_text_array(row['allowed_tools'])
        tools = tool_specs_for_allowlist(tools_list)

        tools_disabled = tools_list.is_a?(Array) && tools_list.empty?
        instr = row['instructions']
        {
          session_id: "council-#{session_id}",
          agent_name: agent_name || row['name'] || row['agent_name'] || 'agent',
          persona: persona_data || { name: 'savant-engineer' },
          driver: driver_data,
          rules: { agent_rulesets: rules_data, global_amr: {} },
          instructions: instr,
          tools_available: tools_disabled ? [] : tools[:available],
          tools_catalog: tools_disabled ? [] : tools[:catalog],
          goal_text: goal_text,
          correlation_id: corr
        }
      end

      def tool_specs_for_allowlist(allowlist)
        mux = Savant::Framework::Runtime.current&.multiplexer
        specs = mux ? (mux.tools || []) : []
        names = specs.map { |s| (s[:name] || s['name']).to_s }.compact.reject(&:empty?)
        if allowlist.is_a?(Array)
          if allowlist.empty?
            names = []
            specs = []
          else
            allowed = allowlist.map(&:to_s)
            names = names.select { |n| allowed.include?(n) || allowed.include?(n.tr('.', '/')) || allowed.include?(n.tr('/', '.')) }
            specs = specs.select do |s|
              n = (s[:name] || s['name']).to_s
              allowed.include?(n) || allowed.include?(n.tr('.', '/')) || allowed.include?(n.tr('/', '.'))
            end
          end
        end
        catalog = specs.map do |s|
          n = (s[:name] || s['name']).to_s
          d = (s[:description] || s['description'] || '').to_s
          next nil if n.empty?

          "- #{n} — #{d}"
        end.compact
        { available: (names + names.map { |n| n.tr('/', '.') }).uniq.sort, catalog: catalog }
      end

      def tool_allowed?(tool_name, payload)
        list = payload[:tools_available] || payload['tools_available'] || []
        name = tool_name.to_s
        list.include?(name) || list.include?(name.tr('.', '/')) || list.include?(name.tr('/', '.'))
      end

      def normalize_msg(m)
        {
          id: m['id'].to_i,
          role: m['role'],
          agent_name: m['agent_name'],
          run_id: m['run_id']&.to_i,
          status: m['status'],
          correlation_id: m['correlation_id'],
          job_id: m['job_id'],
          run_key: m['run_key'],
          text: m['text'],
          created_at: m['created_at']
        }
      end

      def council_intent_async?
        # Always async: council steps submit jobs and return immediately.
        true
      end

      def council_reasoning_callback_url
        base = ENV['COUNCIL_ASYNC_CALLBACK_URL'].to_s.strip
        return base unless base.empty?

        hub = ENV['SAVANT_HUB_URL'].to_s.strip
        if hub.empty?
          host = ENV.fetch('SAVANT_HUB_HOST', '127.0.0.1').to_s.strip
          port = ENV.fetch('SAVANT_HUB_PORT', '9999').to_s.strip
          hub = "http://#{host}:#{port}"
        end
        return nil if hub.empty?

        "#{hub.sub(%r{/+$}, '')}/callbacks/reasoning/agent_intent"
      end
    end
  end
end
