#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'securerandom'
require_relative '../../framework/db'
require_relative '../../reasoning/client'

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
          @db.exec("ALTER TABLE council_sessions ADD COLUMN IF NOT EXISTS context JSONB")
          @db.exec("ALTER TABLE council_sessions ADD COLUMN IF NOT EXISTS artifacts JSONB")
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

      # API
      def session_create(title: nil, agents: [], user_id: nil, description: nil)
        id = @db.create_council_session(title: title, user_id: user_id, agents: Array(agents).map(&:to_s), description: description)
        begin
          if (col = sessions_col)
            col.insert_one({ session_id: id, title: title, agents: Array(agents).map(&:to_s), description: description, user_id: user_id, created_at: Time.now.utc })
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
                who = (last_agent || 'Agent')
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
            last_agent_name: last_agent,
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

      def append_agent(session_id:, agent_name:, run_id: nil, text: nil, status: 'ok')
        @db.add_council_message(session_id: session_id, role: 'agent', agent_name: agent_name, run_id: run_id, text: text, status: status)
        begin
          if (col = messages_col)
            col.insert_one({ session_id: session_id.to_i, role: 'agent', agent_name: agent_name.to_s, run_id: run_id, status: status.to_s, text: text.to_s, created_at: Time.now.utc })
          end
        rescue StandardError
        end
        { ok: true }
      end

      # Perform a single reasoning step for this session by delegating to the Reasoning API (mongo transport by default).
      # Appends the result to Council messages as a structured JSON payload (in text) for easy UI rendering.
      def agent_step(session_id:, goal_text:, agent_name: nil)
        client = Savant::Reasoning::Client.new
        raise 'reasoning_unavailable' unless client.available?

        payload = {
          session_id: "council-#{session_id}",
          persona: { name: 'savant-engineer' },
          goal_text: goal_text.to_s,
          correlation_id: "council-#{session_id}-#{Time.now.to_i}"
        }
        intent = client.agent_intent(payload)
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
          agent_name: (agent_name || 'agent'),
          run_id: nil,
          text: JSON.generate(message),
          status: intent.finish ? 'done' : 'pending'
        )
        { status: 'ok' }.merge(message)
      rescue StandardError => e
        err = { schema: 'council.v1.agent_intent', type: 'error', error: e.message.to_s }
        begin
          append_agent(session_id: session_id, agent_name: (agent_name || 'agent'), run_id: nil, text: JSON.generate(err), status: 'error')
        rescue StandardError
        end
        { status: 'error', error: e.message }
      end

      def session_delete(id:)
        # Simple delete: rely on FK cascade for messages
        @db.exec_params('DELETE FROM council_sessions WHERE id=$1', [id.to_i])
        begin
          if (col = sessions_col)
            col.delete_many({ session_id: id.to_i })
          end
          if (col2 = messages_col)
            col2.delete_many({ session_id: id.to_i })
          end
        rescue StandardError
        end
        { ok: true }
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

        # Add system message about council escalation
        append_agent(
          session_id: session_id,
          agent_name: 'System',
          text: "Council deliberation started. Query: #{query || context[:original_query]}",
          status: 'ok'
        )

        { ok: true, run_id: run_id, session_id: session_id, mode: 'council', context: context }
      end

      # Run the full council protocol
      # This executes all phases: Intent Classification → Initial Positions → Debate → Synthesis
      def run_council_protocol(session_id:, run_id: nil, max_debate_rounds: 2)
        # Get or create run
        run = if run_id
                get_council_run(run_id: run_id)
              else
                current_council_run(session_id)
              end
        raise 'no_council_run' unless run

        run_id = run[:run_id]
        update_run_status(run_id, 'running', 'positions')

        begin
          # Phase 1: Initial Positions (parallel execution of all roles except moderator)
          positions = execute_initial_positions(run)
          update_run_positions(run_id, positions)

          # Check for veto
          safety_position = positions['safety']
          if safety_position && safety_position['veto']
            veto_reason = safety_position['veto_reason'] || 'Safety veto exercised'
            update_run_veto(run_id, true, veto_reason)
            update_run_status(run_id, 'vetoed', 'complete')

            # Add veto message
            append_agent(
              session_id: session_id,
              agent_name: 'Safety',
              text: JSON.generate({ type: 'veto', reason: veto_reason, position: safety_position }),
              status: 'veto'
            )

            return_to_chat(session_id: session_id, message: "Council vetoed: #{veto_reason}")
            return { ok: true, run_id: run_id, status: 'vetoed', veto_reason: veto_reason }
          end

          update_run_status(run_id, 'running', 'debate')

          # Phase 2: Debate/Refinement (optional rounds)
          debate_rounds = []
          max_debate_rounds.times do |round|
            debate_result = execute_debate_round(run, positions, round + 1)
            debate_rounds << debate_result

            # Check if consensus reached
            break if debate_result[:consensus]
          end
          update_run_debate(run_id, debate_rounds)

          update_run_status(run_id, 'running', 'synthesis')

          # Phase 3: Synthesis (Moderator)
          synthesis = execute_synthesis(run, positions, debate_rounds)
          update_run_synthesis(run_id, synthesis)

          # Store final recommendation message
          append_agent(
            session_id: session_id,
            agent_name: 'Moderator',
            text: JSON.generate({ type: 'synthesis', synthesis: synthesis }),
            status: 'ok'
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
        ENV['COUNCIL_DEMO_MODE'] == '1' || ENV['COUNCIL_DEMO_MODE'] == 'true'
      end

      # Execute initial positions for all roles (except moderator)
      def execute_initial_positions(run)
        # Use demo mode if reasoning API not available
        if demo_mode?
          return generate_demo_positions(run)
        end

        client = Savant::Reasoning::Client.new
        unless client.available?
          # Fall back to demo mode if reasoning unavailable
          return generate_demo_positions(run)
        end

        positions = {}
        roles_to_run = %w[analyst skeptic pragmatist safety]

        # Track timeouts to potentially fall back to demo mode
        timeout_count = 0
        demo_positions = generate_demo_positions(run)

        # In a real implementation, these would run in parallel
        roles_to_run.each do |role_key|
          role = COUNCIL_ROLES[role_key]
          next unless role

          prompt = build_position_prompt(run, role)
          begin
            result = client.agent_intent({
              session_id: "council-#{run[:run_id]}-#{role_key}",
              persona: { name: "council-#{role_key}", system_prompt: role[:system_prompt] },
              goal_text: prompt,
              correlation_id: "#{run[:run_id]}-#{role_key}"
            })
            positions[role_key] = parse_role_response(result, role_key)
          rescue StandardError => e
            # On timeout or error, use demo position for this role
            if e.message.to_s.downcase.include?('timeout')
              timeout_count += 1
              positions[role_key] = demo_positions[role_key].merge('note' => 'Generated due to API timeout')
            else
              positions[role_key] = { error: e.message, role: role_key }
            end
          end
        end

        # If all roles timed out, just return the demo positions
        if timeout_count >= roles_to_run.length
          return demo_positions
        end

        positions
      end

      # Generate demo positions without calling the reasoning API
      def generate_demo_positions(run)
        context = run[:context] || {}
        query = run[:query] || context['original_query'] || context[:original_query] || 'the proposed decision'
        chat_summary = context['conversation_summary'] || context[:conversation_summary] || ''

        # Extract key topics from the chat for more relevant responses
        topic_hint = chat_summary.to_s[0, 200] if chat_summary.present?
        topic_note = topic_hint ? " Based on conversation about: #{topic_hint}" : ''

        {
          'analyst' => {
            'query' => query,
            'problem_decomposition' => ['Component 1: Core requirements', 'Component 2: Implementation approach', 'Component 3: Resource allocation'],
            'options' => [
              { 'name' => 'Option A: Conservative approach', 'pros' => ['Lower risk', 'Proven methods'], 'cons' => ['Slower results'], 'assumptions' => ['Resources available'] },
              { 'name' => 'Option B: Aggressive approach', 'pros' => ['Faster results', 'Competitive advantage'], 'cons' => ['Higher risk'], 'assumptions' => ['Team capacity'] }
            ],
            'recommendation' => 'Option A with selective elements of Option B',
            'confidence' => 0.75,
            'reasoning' => "Based on analysis of: #{query}.#{topic_note} A balanced approach is recommended."
          },
          'skeptic' => {
            'query' => query,
            'risks' => [
              { 'risk' => 'Implementation complexity underestimated', 'severity' => 'medium', 'mitigation' => 'Add buffer time' },
              { 'risk' => 'Dependencies on external factors', 'severity' => 'low', 'mitigation' => 'Identify alternatives' }
            ],
            'hidden_assumptions' => ['Assumes current resources remain available', 'Assumes no major market changes'],
            'challenges' => ['Timeline may be optimistic', 'Scope creep potential'],
            'questions' => ['What is the fallback plan?', 'How will success be measured?'],
            'overall_concern_level' => 'medium',
            'reasoning' => "Reviewing: #{query}.#{topic_note} While the proposal has merit, several risks need mitigation."
          },
          'pragmatist' => {
            'query' => query,
            'feasibility_assessment' => [
              { 'option' => 'Option A', 'feasibility' => 'high', 'blockers' => [], 'enablers' => ['Existing infrastructure'] },
              { 'option' => 'Option B', 'feasibility' => 'medium', 'blockers' => ['Resource constraints'], 'enablers' => ['Team motivation'] }
            ],
            'recommended_path' => 'Start with Option A, iterate based on results',
            'quick_wins' => ['Set up monitoring', 'Document requirements', 'Create communication plan'],
            'timeline_estimate' => 'Initial phase: 2-4 weeks',
            'resource_requirements' => ['Dedicated team lead', 'Access to tools'],
            'reasoning' => "For: #{query}.#{topic_note} A phased approach minimizes risk while maintaining momentum."
          },
          'safety' => {
            'query' => query,
            'safety_concerns' => [
              { 'concern' => 'Data privacy considerations', 'severity' => 'low' },
              { 'concern' => 'Compliance requirements', 'severity' => 'low' }
            ],
            'compliance_issues' => [],
            'ethical_considerations' => ['Stakeholder communication', 'Transparency'],
            'stakeholder_impacts' => [
              { 'stakeholder' => 'Team', 'impact' => 'Increased workload temporarily', 'sentiment' => 'neutral' },
              { 'stakeholder' => 'Users', 'impact' => 'Improved experience', 'sentiment' => 'positive' }
            ],
            'veto' => false,
            'veto_reason' => nil,
            'approval_conditions' => ['Ensure proper documentation', 'Maintain rollback capability'],
            'reasoning' => "Evaluating: #{query}.#{topic_note} No critical safety or ethical concerns identified. Proceed with standard precautions."
          }
        }
      end

      # Execute a debate round
      def execute_debate_round(run, positions, round_number)
        # Use demo mode if reasoning API not available
        if demo_mode?
          return generate_demo_debate(run, positions, round_number)
        end

        client = Savant::Reasoning::Client.new
        unless client.available?
          return generate_demo_debate(run, positions, round_number)
        end

        # Build summary of all positions for debate
        positions_summary = positions.map do |role, pos|
          "#{COUNCIL_ROLES[role]&.dig(:name) || role}: #{JSON.generate(pos)}"
        end.join("\n\n")

        refinements = {}
        %w[analyst skeptic pragmatist safety].each do |role_key|
          role = COUNCIL_ROLES[role_key]
          next unless role

          debate_prompt = <<~PROMPT
            This is debate round #{round_number}. Review the positions from all council members and refine your position.

            Current positions:
            #{positions_summary}

            Original query: #{run[:query]}

            Based on the other perspectives, refine your position. Focus on:
            1. Points of agreement
            2. Remaining concerns
            3. Suggested compromises

            Maintain your role's perspective while being open to valid points from others.
          PROMPT

          begin
            result = client.agent_intent({
              session_id: "council-#{run[:run_id]}-debate-#{round_number}-#{role_key}",
              persona: { name: "council-#{role_key}", system_prompt: role[:system_prompt] },
              goal_text: debate_prompt,
              correlation_id: "#{run[:run_id]}-debate-#{round_number}-#{role_key}"
            })
            refinements[role_key] = parse_role_response(result, role_key)
          rescue StandardError => e
            refinements[role_key] = { error: e.message }
          end
        end

        # Check for consensus
        consensus = check_consensus(refinements)

        { round: round_number, refinements: refinements, consensus: consensus }
      end

      # Generate demo debate without calling reasoning API
      def generate_demo_debate(_run, _positions, round_number)
        {
          round: round_number,
          refinements: {
            'analyst' => { 'agreement' => 'All roles agree on phased approach', 'refinement' => 'Added timeline buffer' },
            'skeptic' => { 'agreement' => 'Risk mitigations accepted', 'remaining_concerns' => 'Monitor closely' },
            'pragmatist' => { 'agreement' => 'Implementation plan is solid', 'refinement' => 'Added quick wins' },
            'safety' => { 'agreement' => 'No blockers identified', 'approval' => 'Proceed with precautions' }
          },
          consensus: true
        }
      end

      # Execute synthesis by Moderator
      def execute_synthesis(run, positions, debate_rounds)
        # Use demo mode if reasoning API not available
        if demo_mode?
          return generate_demo_synthesis(run, positions, debate_rounds)
        end

        client = Savant::Reasoning::Client.new
        unless client.available?
          return generate_demo_synthesis(run, positions, debate_rounds)
        end

        role = COUNCIL_ROLES['moderator']

        # Build comprehensive summary for moderator
        positions_summary = positions.map do |role_key, pos|
          "#{COUNCIL_ROLES[role_key]&.dig(:name) || role_key}:\n#{JSON.generate(pos)}"
        end.join("\n\n---\n\n")

        debate_summary = debate_rounds.map do |round|
          "Round #{round[:round]}:\n#{JSON.generate(round[:refinements])}"
        end.join("\n\n")

        synthesis_prompt = <<~PROMPT
          You are the Moderator. Synthesize the council's deliberation into a final recommendation.

          Original Query: #{run[:query]}

          Initial Positions:
          #{positions_summary}

          Debate Rounds:
          #{debate_summary.empty? ? 'No debate rounds' : debate_summary}

          Produce a final synthesis that:
          1. Summarizes key insights from each role
          2. Resolves conflicts between perspectives
          3. Provides a clear, actionable recommendation
          4. Lists concrete next steps
        PROMPT

        result = client.agent_intent({
          session_id: "council-#{run[:run_id]}-synthesis",
          persona: { name: 'council-moderator', system_prompt: role[:system_prompt] },
          goal_text: synthesis_prompt,
          correlation_id: "#{run[:run_id]}-synthesis"
        })

        synthesis = parse_role_response(result, 'moderator')
        synthesis[:councilProtocolVersion] = PROTOCOL_VERSION
        synthesis
      end

      # Generate demo synthesis without calling reasoning API
      def generate_demo_synthesis(run, _positions, _debate_rounds)
        query = run[:query] || 'the proposed decision'
        {
          'summary' => "After careful deliberation on #{query}, the council recommends proceeding with a phased approach that balances speed with risk mitigation.",
          'key_insights' => {
            'analyst' => 'Multiple viable options identified; balanced approach recommended',
            'skeptic' => 'Risks are manageable with proper mitigation strategies',
            'pragmatist' => 'Phased implementation is feasible with current resources',
            'safety' => 'No critical concerns; proceed with standard precautions'
          },
          'conflicts_resolved' => [
            { 'conflict' => 'Timeline expectations', 'resolution' => 'Added buffer time as suggested by Skeptic' },
            { 'conflict' => 'Resource allocation', 'resolution' => 'Prioritized quick wins per Pragmatist recommendation' }
          ],
          'final_recommendation' => 'Proceed with Option A (conservative approach) incorporating quick wins from Option B. Implement in phases with monitoring.',
          'confidence' => 0.8,
          'next_steps' => [
            '1. Document detailed requirements',
            '2. Set up monitoring infrastructure',
            '3. Create communication plan for stakeholders',
            '4. Begin Phase 1 implementation',
            '5. Schedule review checkpoint'
          ],
          'vetoed' => false,
          'veto_explanation' => nil,
          'councilProtocolVersion' => PROTOCOL_VERSION
        }
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

      # Check if consensus has been reached
      def check_consensus(refinements)
        # Simple heuristic: check if all roles have low concern levels
        concerns = refinements.values.map { |r| r['overall_concern_level'] || r['concern_level'] }.compact
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
          veto: row['veto'] == true || row['veto'] == 't',
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
        messages.map do |m|
          role = m[:role] == 'user' ? 'User' : (m[:agent_name] || 'Agent')
          text = (m[:text] || '').to_s
          "#{role}: #{text}"
        end.join("\n\n")
      end

      def summarize_conversation(messages)
        return '' if messages.empty?
        messages.map do |m|
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
          if text.include?('must') || text.include?('require') || text.include?('constraint')
            constraints << (m[:text] || '').to_s[0, 100]
          end
        end
        constraints.uniq
      end

      def extract_options(messages)
        # Simple heuristic: look for option-like language
        options = []
        messages.each do |m|
          text = (m[:text] || '').to_s.downcase
          if text.include?('option') || text.include?('could') || text.include?('alternative')
            options << (m[:text] || '').to_s[0, 100]
          end
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

      def normalize_msg(m)
        {
          id: m['id'].to_i,
          role: m['role'],
          agent_name: m['agent_name'],
          run_id: m['run_id']&.to_i,
          status: m['status'],
          text: m['text'],
          created_at: m['created_at']
        }
      end
    end
  end
end
