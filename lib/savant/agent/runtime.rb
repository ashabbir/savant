#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../logging/logger'
require 'digest'
require_relative '../logging/event_recorder'
require_relative '../framework/engine/runtime_context'
require_relative 'cancel'
require_relative '../llm/adapter'
require_relative 'prompt_builder'
require_relative 'output_parser'
require_relative 'memory'
require_relative '../reasoning/client'
require_relative 'state_machine'

module Savant
  module Agent
    # Orchestrates the reasoning loop using the external Reasoning API for decisions.
    class Runtime
      DEFAULT_MAX_STEPS = (ENV['AGENT_MAX_STEPS'] || '25').to_i

      attr_accessor :agent_instructions, :agent_rulesets, :agent_llm, :state_machine, :system_message

      def initialize(goal:, llm_model: nil, logger: nil, base_path: nil, forced_tool: nil, forced_args: nil, forced_finish: false, forced_final: nil, cancel_key: nil, run_id: nil)
        @goal = goal.to_s
        @context = Savant::Framework::Runtime.current
        @base_path = base_path || default_base_path
        lvl = ENV['LOG_LEVEL'] || 'error'
        io = ENV['SAVANT_QUIET'] == '1' ? nil : $stdout
        @logger = logger || Savant::Logging::MongoLogger.new(service: 'agent')
        # Use global recorder so Diagnostics/Logs (events) can display agent telemetry.
        @trace = Savant::Logging::EventRecorder.global
        @trace_file_path = File.join(@base_path, 'logs', 'agent_trace.log')
        @memory = Savant::Agent::Memory.new(base_path: @base_path, logger: @logger)
        @prompt_builder = Savant::Agent::PromptBuilder.new(runtime: @context, logger: @logger)
        @llm_model = llm_model || Savant::LLM::DEFAULT_LLM
        @max_steps = DEFAULT_MAX_STEPS
        @last_output = nil
        @forced_tool = forced_tool&.to_s
        @forced_args = forced_args.is_a?(Hash) ? forced_args : {}
        @forced_tool_used = false
        @forced_finish = !!forced_finish
        @forced_final = forced_final&.to_s
        @cancel_key = cancel_key
        @run_id = run_id
        @agent_instructions = nil
        @agent_rulesets = nil
        @agent_llm = nil
        @state_machine = Savant::Agent::StateMachine.new
        @system_message = nil
      end

      def run(max_steps: @max_steps, dry_run: false)
        steps = 0
        model = 'reasoning_api/v1'
        # AMR shortcut: if goal clearly requests a workflow, auto-trigger workflow_run once.
        # Default: ENABLED (AGENT_ENABLE_WORKFLOW_AUTODETECT=1 implicit). You can disable with AGENT_DISABLE_WORKFLOW_AUTODETECT=1 or FORCE_REASONING_API=1.
        autodetect = true
        begin
          env_true  = ->(v) { v && %w[1 true yes on].include?(v.to_s.strip.downcase) }
          env_false = ->(v) { v && %w[0 false no off].include?(v.to_s.strip.downcase) }

          en = ENV['AGENT_ENABLE_WORKFLOW_AUTODETECT']
          dis = ENV['AGENT_DISABLE_WORKFLOW_AUTODETECT']
          force = ENV['FORCE_REASONING_API']

          # Explicit disables take precedence
          if env_true.call(dis) || env_true.call(force)
            autodetect = false
          elsif env_false.call(en)
            autodetect = false
          elsif env_true.call(en)
            autodetect = true
          else
            # No overrides -> keep default true
            autodetect = true
          end
        rescue StandardError
          autodetect = true
        end
        if !@forced_tool && autodetect
          begin
            auto = detect_workflow_intent(@goal)
            if auto
              @forced_tool = 'workflow.workflow_run'
              @forced_args = { 'workflow' => auto[:workflow], 'params' => auto[:params] || {} }
              # Finish after first step to hand results back deterministically.
              @forced_finish = true if @forced_final.nil?
            end
          rescue StandardError
            # ignore AMR shortcut errors
          end
        end
        loop do
          # Cooperative cancellation check
          if @cancel_key && Savant::Agent::Cancel.signal?(@cancel_key)
            final_text = 'Canceled by user'
            finish_action = { 'action' => 'finish', 'tool_name' => '', 'args' => {}, 'final' => final_text, 'reasoning' => 'canceled' }
            @memory.append_step(index: steps + 1, action: finish_action, final: final_text)
            @memory.snapshot!
            emit_step_event(steps: steps + 1, model: nil, usage: {}, action: finish_action)
            return { status: 'canceled', steps: steps + 1, final: final_text, memory_path: @memory.path, transcript: @memory.full_data }
          end
          steps += 1

          # Tick state machine
          @state_machine.tick

          # Check if agent is stuck
          if @state_machine.stuck?
            stuck_msg = @state_machine.suggest_exit
            final_text = "Agent stuck: #{stuck_msg}"
            finish_action = { 'action' => 'finish', 'tool_name' => '', 'args' => {}, 'final' => final_text, 'reasoning' => 'stuck_detection' }
            @memory.append_step(index: steps, action: finish_action, final: final_text)
            @memory.snapshot!
            emit_step_event(steps: steps, model: nil, usage: {}, action: finish_action)
            return { status: 'ok', steps: steps, final: final_text, memory_path: @memory.path, transcript: @memory.full_data }
          end

          if steps > max_steps
            # Gracefully finish if step cap reached
            final_text = "Reached maximum steps (#{max_steps})."
            finish_action = { 'action' => 'finish', 'tool_name' => '', 'args' => {}, 'final' => final_text, 'reasoning' => 'max_steps' }
            @memory.append_step(index: steps, action: finish_action, final: final_text)
            @memory.snapshot!
            emit_step_event(steps: steps, model: nil, usage: {}, action: finish_action)
            return { status: 'ok', steps: steps, final: final_text, memory_path: @memory.path, transcript: @memory.full_data }
          end

          # Forced tool execution (one-shot): execute specified tool as the first step
          if @forced_tool && !@forced_tool_used
            # Enforce default policy: block Think tools unless explicitly allowed
            if @forced_tool.start_with?('think.') && !env_bool('AGENT_ALLOW_THINK_TOOLS')
              final_text = 'Think tools are disabled by default for agents.'
              finish_action = { 'action' => 'finish', 'tool_name' => '', 'args' => {}, 'final' => final_text, 'reasoning' => 'think_tools_disabled' }
              @memory.append_step(index: steps, action: finish_action, final: final_text)
              @memory.snapshot!
              emit_step_event(steps: steps, model: nil, usage: {}, action: finish_action)
              return { status: 'ok', steps: steps, final: final_text, memory_path: @memory.path, transcript: @memory.full_data }
            end

            result = if dry_run
                       { dry: true, tool: @forced_tool, args: @forced_args }
                     else
                       call_tool(@forced_tool, @forced_args, step: steps)
                     end
            @last_output = safe_json(result)
            @memory.append_step(index: steps, action: { 'action' => 'tool', 'tool_name' => @forced_tool, 'args' => @forced_args, 'final' => '', 'reasoning' => 'forced' }, output: result)
            @memory.snapshot!
            @forced_tool_used = true
            if @forced_finish
              # Append a finish step and return
              finish_index = steps + 1
              final_text = @forced_final && !@forced_final.empty? ? @forced_final : "Finished after #{@forced_tool}."
              finish_action = { 'action' => 'finish', 'tool_name' => '', 'args' => {}, 'final' => final_text, 'reasoning' => 'forced' }
              @memory.append_step(index: finish_index, action: finish_action, final: final_text)
              @memory.snapshot!
              emit_step_event(steps: finish_index, model: nil, usage: {}, action: finish_action)
              return { status: 'ok', steps: finish_index, final: final_text, memory_path: @memory.path, transcript: @memory.full_data }
            end
            next
          end

          # Forced finish without tool: stop immediately with a finish step
          if @forced_finish && !@forced_tool
            final_text = @forced_final && !@forced_final.empty? ? @forced_final : 'Finished by request.'
            finish_action = { 'action' => 'finish', 'tool_name' => '', 'args' => {}, 'final' => final_text, 'reasoning' => 'forced' }
            @memory.append_step(index: steps, action: finish_action, final: final_text)
            @memory.snapshot!
            emit_step_event(steps: steps, model: nil, usage: {}, action: finish_action)
            return { status: 'ok', steps: steps, final: final_text, memory_path: @memory.path, transcript: @memory.full_data }
          end

          tool_specs = begin
            @context&.multiplexer&.tools || []
          rescue StandardError
            []
          end
          # Filter tools by policy: restrict to state-allowed tools when present,
          # and avoid Think tools that require a workflow unless explicitly in workflow mode.
          filtered_specs = filter_tool_specs(tool_specs)
          base_tools = filtered_specs.map { |s| (s[:name] || s['name']).to_s }.compact.reject(&:empty?)
          tools_hint = (base_tools + base_tools.map { |n| n.gsub('/', '.') }).uniq.sort
          catalog = filtered_specs.map do |s|
            n = (s[:name] || s['name']).to_s
            d = (s[:description] || s['description'] || '').to_s
            next nil if n.empty?

            # Include required parameters info
            schema = s[:schema] || s['schema']
            required = schema&.dig(:required) || schema&.dig('required') || []
            req_info = required.any? ? " (required: #{required.join(', ')})" : ''

            "- #{n} — #{d}#{req_info}"
          end.compact
          # Compose a system note communicating tool policy so the Reasoning API avoids disallowed tools.
          pol = instruction_tool_policy
          policy_note = if pol[:disable_all]
            'Tool Policy: Tools are disabled by instruction. Always choose action="reason" or "finish"; do not select any tool.'
          elsif pol[:disable_context] || pol[:disable_search]
            dis = []
            dis << 'context tools' if pol[:disable_context]
            dis << 'search tools' if pol[:disable_search]
            "Tool Policy: Avoid #{dis.join(' and ')} per instruction. Prefer reasoning and finishing without tools."
          else
            nil
          end
          system_msg = [@system_message, policy_note].compact.join("\n\n")
          prompt = @prompt_builder.build(goal: @goal, memory: @memory.data, last_output: @last_output, tools_hint: tools_hint, tools_catalog: catalog, agent_instructions: @agent_instructions, system: system_msg)
          begin
            ps = { type: 'prompt_snapshot', mcp: 'agent', run: @run_id, step: steps, length: prompt.length, hash: Digest::SHA256.hexdigest(prompt)[0, 16], text: prompt[0, 1500], ts: Time.now.utc.iso8601, timestamp: Time.now.to_i }
            @trace.record(ps)
            append_trace_file(ps)
          rescue StandardError
            # ignore
          end
          action, usage, model = decide_and_parse(prompt: prompt, model: model, allowed_tools: base_tools, step: steps, dry_run: dry_run)
          # Re-check cancellation after potentially long LLM call
          if @cancel_key && Savant::Agent::Cancel.signal?(@cancel_key)
            final_text = 'Canceled by user'
            finish_action = { 'action' => 'finish', 'tool_name' => '', 'args' => {}, 'final' => final_text, 'reasoning' => 'canceled' }
            @memory.append_step(index: steps + 1, action: finish_action, final: final_text)
            @memory.snapshot!
            emit_step_event(steps: steps + 1, model: nil, usage: {}, action: finish_action)
            return { status: 'canceled', steps: steps + 1, final: final_text, memory_path: @memory.path, transcript: @memory.full_data }
          end
          emit_step_event(steps: steps, model: model, usage: usage, action: action)
          begin
            act = (action['action'] || '').to_s
            tool = (action['tool_name'] || '').to_s
            summary = (action['reasoning'] || action['final'] || '').to_s[0, 200]
            guide = { type: 'step_guide', mcp: 'agent', run: @run_id, step: steps, text: "Run #{@run_id} > Step #{steps} > #{act}#{tool.empty? ? '' : " #{tool}"}", explanation: summary, ts: Time.now.utc.iso8601, timestamp: Time.now.to_i }
            @trace.record(guide)
            append_trace_file(guide)
          rescue StandardError
          end

          # If tool action requested, ensure tool exists or ask for correction once
          action = ensure_valid_action(action, base_tools)

        case action['action']
        when 'tool'
          # Before calling any tool, record a brief rationale so UIs can show "why"
          begin
            rationale = (action['reasoning'] || '').to_s
            explain = rationale.empty? ? "Planning to call #{action['tool_name']}" : "Planning to call #{action['tool_name']} because: #{rationale}"
            @memory.append_step(index: steps, action: { 'action' => 'reason', 'tool_name' => '', 'args' => {}, 'final' => '', 'reasoning' => explain })
          rescue StandardError
          end
          # Check cancellation just before calling a potentially long-running tool
          if @cancel_key && Savant::Agent::Cancel.signal?(@cancel_key)
            final_text = 'Canceled by user'
            finish_action = { 'action' => 'finish', 'tool_name' => '', 'args' => {}, 'final' => final_text, 'reasoning' => 'canceled' }
            @memory.append_step(index: steps, action: finish_action, final: final_text)
              @memory.snapshot!
              emit_step_event(steps: steps, model: nil, usage: {}, action: finish_action)
              return { status: 'canceled', steps: steps, final: final_text, memory_path: @memory.path, transcript: @memory.full_data }
            end

            # Record tool call in state machine
            tool_name = action['tool_name']
            tool_args = action['args'] || {}
            @state_machine.record_tool_call(tool_name, tool_args)

            # Transition to appropriate state based on tool
            next_state = @state_machine.infer_state_from_tool(tool_name)
            @state_machine.transition_to(next_state, reason: tool_name) if next_state

            res = dry_run ? { dry: true, tool: action['tool_name'], args: action['args'] } : call_tool(action['tool_name'], action['args'], step: steps)
            @last_output = safe_json(res)
            @memory.append_step(index: steps, action: action, output: res)
            @memory.snapshot!
          when 'reason'
            # Log as Reasoning API; no local LLM calls here
            model = 'reasoning_api/v1'
            @state_machine.transition_to(:analyzing, reason: 'deep_reasoning')
            @last_output = action['reasoning']
            @memory.append_step(index: steps, action: action, note: 'deep_reasoning')
            @memory.snapshot!
          when 'finish'
            @state_machine.transition_to(:finishing, reason: 'finish_action')
            @memory.append_step(index: steps, action: action, final: action['final'])
            @memory.snapshot!
            return { status: 'ok', steps: steps, final: action['final'], memory_path: @memory.path, transcript: @memory.full_data }
          when 'error'
            @state_machine.transition_to(:finishing, reason: 'error')
            @memory.append_error(action)
            @memory.snapshot!
            return { status: 'error', steps: steps, error: action['final'] || 'agent_error', memory_path: @memory.path, transcript: @memory.full_data }
          else
            @memory.append_error({ type: 'invalid_action', raw: action })
            @memory.snapshot!
            return { status: 'error', steps: steps, error: 'invalid_action' }
          end
        end

        { status: 'stopped', reason: 'max_steps', steps: max_steps, memory_path: @memory.path, transcript: @memory.full_data }
      end

      private

      def env_bool(name)
        v = ENV[name]
        return false if v.nil?
        %w[1 true yes on].include?(v.to_s.strip.downcase)
      end

      # Determine whether the agent is explicitly in a workflow-driving mode.
      def workflow_mode?
        return true if @forced_tool && @forced_tool.start_with?('workflow.')
        # Heuristic: if goal explicitly references a known workflow name
        !!detect_workflow_intent(@goal)
      rescue StandardError
        false
      end

      # Return filtered tool specs based on state + workflow policy.
      def filter_tool_specs(specs)
        return [] unless specs.is_a?(Array)

        # Instruction-derived policy
        pol = instruction_tool_policy

        # Global toggles to disable tools via env, merged with instruction policy
        disable_all = env_bool('AGENT_DISABLE_TOOLS') || env_bool('DISABLE_MCP') || pol[:disable_all]
        return [] if disable_all

        disable_context = env_bool('AGENT_DISABLE_CONTEXT_TOOLS') || pol[:disable_context]
        disable_search = env_bool('AGENT_DISABLE_SEARCH_TOOLS') || pol[:disable_search]

        names_allowed_by_state = Array(@state_machine&.allowed_actions)
        # Policy: disable Think tools by default for agents.
        # Set AGENT_ALLOW_THINK_TOOLS=1 to opt-in.
        disable_think = !env_bool('AGENT_ALLOW_THINK_TOOLS')
        in_workflow = workflow_mode?

        specs.select do |s|
          name = (s[:name] || s['name']).to_s
          next false if name.empty?

          # Optionally disable Context tools entirely or only search tools
          if disable_context && name.start_with?('context.')
            next false
          end
          if disable_search && %w[context.fts_search context.memory_search].include?(name)
            next false
          end

          # If state machine specifies a non-empty allowlist, enforce it strictly
          if names_allowed_by_state.any?
            next false unless names_allowed_by_state.include?(name)
          end

          # Optionally disable all Think tools
          if disable_think && name.start_with?('think.')
            next false
          end

          # Avoid Think tools that require a workflow when not in workflow mode
          if name.start_with?('think.') && !in_workflow
            schema = s[:schema] || s['schema']
            req = (schema&.dig(:required) || schema&.dig('required') || []).map(&:to_s)
            if req.include?('workflow')
              next false
            end
          end

          true
        end
      end

      def detect_workflow_intent(goal)
        g = (goal || '').to_s
        return nil if g.empty?

        # If "workflow <name>" present, extract name token
        m = g.match(/workflow\s+([A-Za-z0-9_.-]+)/i)
        if m && m[1]
          name = m[1].downcase
          return { workflow: name } if workflow_exists?(name)

          # Try underscored and hyphen variants
          alt = name.tr('-', '_')
          return { workflow: alt } if workflow_exists?(alt)
        end
        # If code review intent, try common names
        if g =~ /(code\s*review|pull\s*request|mr\b)/i
          %w[code_review review mr_review].each do |cand|
            return { workflow: cand } if workflow_exists?(cand)
          end
        end
        # Default example workflow for demonstration
        return { workflow: 'hello' } if workflow_exists?('hello') && g =~ /(workflow|execute)/i

        nil
      end

      def workflow_exists?(name)
        path = File.join(@base_path, 'workflows', "#{name}.yaml")
        File.file?(path)
      end

      def decide_and_parse(prompt:, model:, allowed_tools: [], step: nil, dry_run: false)
        usage = { prompt_tokens: nil, output_tokens: nil }
        # In dry-run, do not hit external services; finish immediately
        if dry_run
          return [
            { 'action' => 'finish', 'tool_name' => '', 'args' => {}, 'final' => 'ok', 'reasoning' => 'dry_run' },
            usage,
            'reasoning_api/v1'
          ]
        end
        # Always route decisions through the Reasoning API; no local SLM fallback
        payload = build_agent_payload
        intent = reasoning_client.agent_intent(payload)
        parsed = intent_to_action(intent)
        [parsed, usage, 'reasoning_api/v1']
      rescue StandardError => e
        @logger.warn(event: 'agent_decide_failed', error: e.message)
        [
          { 'action' => 'error', 'final' => e.message, 'tool_name' => '', 'args' => {}, 'reasoning' => '' },
          usage,
          'reasoning_api/v1'
        ]
      end

      def build_agent_payload
        ctx = @context
        provider = nil
        model = nil
        api_key = nil

        # Use agent_llm if available (from registered provider/model assignment)
        if @agent_llm && @agent_llm.is_a?(Hash)
          provider = @agent_llm[:provider]
          model = @agent_llm[:llm_model]
          api_key = @agent_llm[:api_key]
        end

        # Fallback to defaults
        provider ||= Savant::LLM.default_provider_for(@llm_model)
        model ||= @llm_model

        llm_obj = {
          provider: provider,
          model: model
        }
        llm_obj[:api_key] = api_key if api_key

        {
          session_id: ctx&.session_id || "run-#{Time.now.to_i}",
          persona: ctx&.persona || {},
          driver: ctx&.driver_prompt || {},
          rules: {
            agent_rulesets: @agent_rulesets || [],
            global_amr: (ctx&.amr_rules || {})
          },
          instructions: @agent_instructions,
          repo_context: ctx&.repo || {},
          memory_state: @memory&.data || {},
          history: @memory&.full_data&.dig('steps') || [],
          goal_text: @goal,
          forced_tool: @forced_tool,
          max_steps: 1,
          llm: llm_obj,
          agent_state: @state_machine&.to_h,
          correlation_id: @run_id
        }
      end

      def intent_to_action(intent)
        if intent.finish
          { 'action' => 'finish', 'tool_name' => '', 'args' => {}, 'final' => intent.final_text.to_s, 'reasoning' => intent.reasoning.to_s }
        elsif intent.tool_name && !intent.tool_name.to_s.empty?
          { 'action' => 'tool', 'tool_name' => intent.tool_name.to_s, 'args' => intent.tool_args || {}, 'final' => '', 'reasoning' => intent.reasoning.to_s }
        else
          { 'action' => 'reason', 'tool_name' => '', 'args' => {}, 'final' => '', 'reasoning' => intent.reasoning.to_s }
        end
      end

      def reasoning_client
        @reasoning_client ||= Savant::Reasoning::Client.new
      end

      # Removed model-based repair path; Reasoning API must return a valid action.

      # If action is 'tool' but tool_name is not allowed, normalize or convert to error/reason.
      def ensure_valid_action(action, valid_tools)
        return action unless action.is_a?(Hash)
        return action unless action['action'] == 'tool'

        name = (action['tool_name'] || '').to_s

        # Tools policy from instructions
        pol = instruction_tool_policy
        tools_disallowed = pol[:disable_all] || env_bool('AGENT_DISABLE_TOOLS')
        context_disallowed = pol[:disable_context]
        search_disallowed = pol[:disable_search]

        # If tools are disabled for this run or by instruction, convert to reasoning explaining why
        if valid_tools.nil? || valid_tools.empty? || tools_disallowed ||
           (context_disallowed && name.start_with?('context.')) ||
           (search_disallowed && %w[context.fts_search context.memory_search].include?(name))
          why = (action['reasoning'] || '').to_s
          msg = "Tool call '#{name}' skipped due to instructions. Rationale: #{why.empty? ? 'n/a' : why}. Proceeding without tools."
          return { 'action' => 'reason', 'tool_name' => '', 'args' => {}, 'final' => '', 'reasoning' => msg }
        end
        return action if valid_tools.include?(name)

        # Try normalizing separators
        norm1 = name.gsub('.', '/')
        name.gsub('/', '.')
        # Only accept corrected canonical name with '/'
        return action.merge('tool_name' => norm1) if valid_tools.include?(norm1)

        # Skip model-based correction; rely on Reasoning API/tool policy and simple heuristics only
        # Heuristic fallback: if goal clearly asks for search/fts, use context.fts_search when available and not prohibited
        unless env_bool('AGENT_DISABLE_CONTEXT_TOOLS') || env_bool('AGENT_DISABLE_SEARCH_TOOLS') || pol[:disable_context] || pol[:disable_search]
          return action.merge('tool_name' => 'context.fts_search') if @goal =~ /\b(search|fts|find|lookup|README)\b/i && valid_tools.include?('context.fts_search')
        end

        # Could not correct; convert to error so loop can finish or try again
        { 'action' => 'error', 'final' => "invalid tool: #{name}", 'tool_name' => name, 'args' => {}, 'reasoning' => '' }
      end



      # Derive tool-use policy heuristically from instructions/system/goal
      def instruction_tool_policy
        begin
          text = [@agent_instructions, @system_message, @goal].compact.map(&:to_s).join("\n\n")
          return { disable_all: false, disable_context: false, disable_search: false } if text.strip.empty?
          lower = text.downcase
          no_tools = !!(lower =~ /(no\s+tools|do not (use|call) (any )?tools|without\s+tools|do not use mcp|no\s+mcp|offline\s+only)/i)
          no_search = !!(lower =~ /(do not (search|lookup)|no\s+(search|fts)|avoid\s+context\s+search)/i)
          no_context = !!(lower =~ /(do not use\s+context\.?|no\s+context\s+tools|no\s+context\s+mcp)/i)
          {
            disable_all: no_tools,
            disable_context: no_tools || no_context,
            disable_search: no_tools || no_search
          }
        rescue StandardError
          { disable_all: false, disable_context: false, disable_search: false }
        end
      end

      def call_tool(name, args, step: nil)
        mux = @context&.multiplexer
        raise StandardError, 'multiplexer_not_available' unless mux

        start_ev = { type: 'tool_call_started', mcp: 'agent', run: @run_id, step: step, tool: name, ts: Time.now.utc.iso8601, timestamp: Time.now.to_i }
        @trace.record(start_ev)
        append_trace_file(start_ev)
        out, dur = @logger.with_timing(label: 'tool_call') { mux.call(name, args || {}) }
        @logger.info(event: 'tool_call', tool: name, duration_ms: dur)
        done_ev = { type: 'tool_call_completed', mcp: 'agent', run: @run_id, step: step, tool: name, duration_ms: dur, ts: Time.now.utc.iso8601, timestamp: Time.now.to_i }
        @trace.record(done_ev)
        append_trace_file(done_ev)
        out
      rescue Savant::Multiplexer::ToolNotFound => e
        @logger.warn(event: 'tool_not_found', tool: name)
        err_ev = { type: 'tool_call_error', mcp: 'agent', run: @run_id, step: step, tool: name, error: 'tool_not_found', ts: Time.now.utc.iso8601, timestamp: Time.now.to_i }
        @trace.record(err_ev)
        append_trace_file(err_ev)
        { error: 'tool_not_found', message: e.message }
      rescue Savant::Multiplexer::EngineOffline => e
        @logger.warn(event: 'engine_offline', tool: name)
        err_ev = { type: 'tool_call_error', mcp: 'agent', run: @run_id, step: step, tool: name, error: 'engine_offline', ts: Time.now.utc.iso8601, timestamp: Time.now.to_i }
        @trace.record(err_ev)
        append_trace_file(err_ev)
        { error: 'engine_offline', message: e.message }
      rescue StandardError => e
        @logger.warn(event: 'tool_call_error', tool: name, error: e.message)
        err_ev = { type: 'tool_call_error', mcp: 'agent', run: @run_id, step: step, tool: name, error: e.message, ts: Time.now.utc.iso8601, timestamp: Time.now.to_i }
        @trace.record(err_ev)
        append_trace_file(err_ev)
        { error: 'tool_call_error', message: e.message }
      end

      # Removed local LLM call wrapper; decisions are handled by the Reasoning API.

      def emit_step_event(steps:, model:, usage:, action:)
        summary = (action['reasoning'] || action[:reasoning] || '').to_s
        summary = (action['final'] || action[:final] || '').to_s if summary.empty?
        summary = summary[0, 200] unless summary.nil?
        ev = {
          mcp: 'agent',
          run: @run_id,
          type: 'reasoning_step',
          step: steps,
          model: model,
          prompt_tokens: usage[:prompt_tokens],
          output_tokens: usage[:output_tokens],
          action: action['action'],
          tool_name: action['tool_name'],
          metadata: {
            decision_summary: summary
          },
          timestamp: Time.now.to_i
        }
        @trace.record(ev)
        append_trace_file(ev)
      rescue StandardError
        # tolerate telemetry failures
      end

      def append_trace_file(event)
        dir = File.dirname(@trace_file_path)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
        File.open(@trace_file_path, 'a') { |f| f.puts(JSON.generate(event)) }
      rescue StandardError
        # ignore file write errors
      end

      def safe_json(obj)
        JSON.parse(JSON.generate(obj))
      end

      def default_base_path
        if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
          ENV['SAVANT_PATH']
        else
          File.expand_path('../../..', __dir__)
        end
      end
    end
  end
end
