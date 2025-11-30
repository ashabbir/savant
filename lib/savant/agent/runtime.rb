#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../logging/logger'
require 'digest'
require_relative '../logging/event_recorder'
require_relative '../framework/engine/runtime_context'
require_relative '../llm/adapter'
require_relative 'prompt_builder'
require_relative 'output_parser'
require_relative 'memory'

module Savant
  module Agent
    # Orchestrates the reasoning loop using SLM for planning and LLM for deep tasks.
    class Runtime
      DEFAULT_MAX_STEPS = (ENV['AGENT_MAX_STEPS'] || '25').to_i

      def initialize(goal:, slm_model: nil, llm_model: nil, logger: nil, base_path: nil, forced_tool: nil, forced_args: nil, forced_finish: false, forced_final: nil)
        @goal = goal.to_s
        @context = Savant::Framework::Runtime.current
        @base_path = base_path || default_base_path
        lvl = ENV['LOG_LEVEL'] || 'error'
        io = ENV['SAVANT_QUIET'] == '1' ? nil : $stdout
        @logger = logger || Savant::Logging::Logger.new(io: io, file_path: File.join(@base_path, 'logs', 'agent_runtime.log'), json: true, service: 'agent', level: lvl)
        # Use global recorder so Diagnostics/Logs (events) can display agent telemetry.
        @trace = Savant::Logging::EventRecorder.global
        @trace_file_path = File.join(@base_path, 'logs', 'agent_trace.log')
        @memory = Savant::Agent::Memory.new(base_path: @base_path, logger: @logger)
        @prompt_builder = Savant::Agent::PromptBuilder.new(runtime: @context, logger: @logger)
        @slm_model = slm_model || Savant::LLM::DEFAULT_SLM
        @llm_model = llm_model || Savant::LLM::DEFAULT_LLM
        @max_steps = DEFAULT_MAX_STEPS
        @last_output = nil
        @forced_tool = forced_tool&.to_s
        @forced_args = forced_args.is_a?(Hash) ? forced_args : {}
        @forced_tool_used = false
        @forced_finish = !!forced_finish
        @forced_final = forced_final&.to_s
      end

      def run(max_steps: @max_steps, dry_run: false)
        steps = 0
        model = @slm_model
        loop do
          steps += 1
          break if steps > max_steps

          # Forced tool execution (one-shot): execute specified tool as the first step
          if @forced_tool && !@forced_tool_used
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
              return { status: 'ok', steps: finish_index, final: final_text, memory_path: @memory.path }
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
            return { status: 'ok', steps: steps, final: final_text, memory_path: @memory.path }
          end

          tool_specs = begin
            @context&.multiplexer&.tools || []
          rescue StandardError
            []
          end
          base_tools = tool_specs.map { |s| (s[:name] || s['name']).to_s }.compact.reject(&:empty?)
          tools_hint = (base_tools + base_tools.map { |n| n.gsub('/', '.') }).uniq.sort
          catalog = tool_specs.map do |s|
            n = (s[:name] || s['name']).to_s
            d = (s[:description] || s['description'] || '').to_s
            next nil if n.empty?

            "- #{n} — #{d}"
          end.compact
          prompt = @prompt_builder.build(goal: @goal, memory: @memory.data, last_output: @last_output, tools_hint: tools_hint, tools_catalog: catalog)
          begin
            ps = { type: 'prompt_snapshot', mcp: 'agent', run: @run_id, step: steps, length: prompt.length, hash: Digest::SHA256.hexdigest(prompt)[0, 16], text: prompt[0, 1500], ts: Time.now.utc.iso8601, timestamp: Time.now.to_i }
            @trace.record(ps)
            append_trace_file(ps)
          rescue StandardError
            # ignore
          end
          action, usage, model = decide_and_parse(prompt: prompt, model: model, allowed_tools: base_tools, step: steps)
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
            res = dry_run ? { dry: true, tool: action['tool_name'], args: action['args'] } : call_tool(action['tool_name'], action['args'], step: steps)
            @last_output = safe_json(res)
            @memory.append_step(index: steps, action: action, output: res)
            @memory.snapshot!
          when 'reason'
            # Escalate to LLM for deeper reasoning
            model = @llm_model
            @last_output = action['reasoning']
            @memory.append_step(index: steps, action: action, note: 'deep_reasoning')
            @memory.snapshot!
          when 'finish'
            @memory.append_step(index: steps, action: action, final: action['final'])
            @memory.snapshot!
            return { status: 'ok', steps: steps, final: action['final'], memory_path: @memory.path }
          when 'error'
            @memory.append_error(action)
            @memory.snapshot!
            return { status: 'error', steps: steps, error: action['final'] || 'agent_error', memory_path: @memory.path }
          else
            @memory.append_error({ type: 'invalid_action', raw: action })
            @memory.snapshot!
            return { status: 'error', steps: steps, error: 'invalid_action' }
          end
        end

        { status: 'stopped', reason: 'max_steps', steps: max_steps, memory_path: @memory.path }
      end

      private

      def decide_and_parse(prompt:, model:, allowed_tools: [], step: nil)
        usage = { prompt_tokens: nil, output_tokens: nil }
        text, usage = with_timing_llm(model: model, prompt: prompt, step: step)
        parsed = parse_action(text) || retry_fix_json(model: model, prompt: prompt, raw: text)
        # If model returned an invalid action, ask for a correction once with stricter instructions
        if parsed.is_a?(Hash) && parsed['action'] == 'error' && (parsed['final'] || '').to_s.downcase.include?('invalid action')
          corrected = repair_invalid_action(model: model, allowed_tools: allowed_tools)
          parsed = corrected if corrected
        end
        [parsed, usage, model]
      rescue StandardError => e
        @logger.warn(event: 'agent_decide_failed', error: e.message)
        [
          { 'action' => 'error', 'final' => e.message, 'tool_name' => '', 'args' => {}, 'reasoning' => '' },
          usage,
          model
        ]
      end

      def repair_invalid_action(model:, allowed_tools: [])
        actions = %w[tool reason finish error]
        tool_list = allowed_tools.take(150).join("\n")
        correction = <<~MD
          Your previous JSON used an invalid "action". You must output exactly one valid JSON object where:
          - action is one of: #{actions.join(', ')}
          - If action = "tool":
              - tool_name must be one of the following valid tools (use slashes '/'):\n#{tool_list}
              - args is a JSON object with parameters
          - If action = "finish": set final to a short summary and leave tool_name empty
          Return ONLY the JSON object, no prose.
        MD
        fixed = Savant::LLM.call(prompt: correction, model: model, json: true, temperature: 0.0)
        Savant::Agent::OutputParser.parse(fixed[:text])
      rescue StandardError
        nil
      end

      # If action is 'tool' but tool_name is not allowed, ask SLM to correct once.
      def ensure_valid_action(action, valid_tools)
        return action unless action.is_a?(Hash)
        return action unless action['action'] == 'tool'

        name = (action['tool_name'] || '').to_s
        return action if valid_tools.include?(name)

        # Try normalizing separators
        norm1 = name.gsub('.', '/')
        name.gsub('/', '.')
        # Only accept corrected canonical name with '/'
        return action.merge('tool_name' => norm1) if valid_tools.include?(norm1)

        # Ask model to correct tool_name given the allowed list
        correction_prompt = <<~MD
          The selected tool "#{name}" is not available. Choose the closest valid tool from this list and return a corrected JSON envelope only:
          #{valid_tools.take(200).join("\n")}
        MD
        begin
          fixed = Savant::LLM.call(prompt: correction_prompt, model: @slm_model, json: true, temperature: 0.0)
          parsed = Savant::Agent::OutputParser.parse(fixed[:text])
          return parsed if parsed['action'] == 'tool' && valid_tools.include?(parsed['tool_name'])
        rescue StandardError
          # fall through
        end
        # Heuristic fallback: if goal clearly asks for search/fts, use context.fts/search when available
        return action.merge('tool_name' => 'context.fts/search') if @goal =~ /\b(search|fts|find|lookup|README)\b/i && valid_tools.include?('context.fts/search')

        # Could not correct; convert to error so loop can finish or try again
        { 'action' => 'error', 'final' => "invalid tool: #{name}", 'tool_name' => name, 'args' => {}, 'reasoning' => '' }
      end

      def parse_action(text)
        Savant::Agent::OutputParser.parse(text)
      rescue StandardError
        nil
      end

      def retry_fix_json(model:, _prompt:, raw:)
        fix_prompt = <<~MD
          The previous output did not match the required JSON schema. Only return a single valid JSON object matching the schema. No prose.
          Previous output:
          ```
          #{raw}
          ```
        MD
        repaired = Savant::LLM.call(prompt: fix_prompt, model: model, json: true)
        Savant::Agent::OutputParser.parse(repaired[:text])
      rescue StandardError => e
        raise StandardError, "unable_to_fix_json: #{e.message}"
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

      def with_timing_llm(model:, prompt:, step: nil)
        result, dur = @logger.with_timing(label: 'llm_call') do
          Savant::LLM.call(prompt: prompt, model: model, temperature: 0.0)
        end
        @logger.info(event: 'llm_call', model: model, duration_ms: dur)
        usage = result[:usage] || {}
        llm_ev = { type: 'llm_call', mcp: 'agent', run: @run_id, step: step, model: model, duration_ms: dur, prompt_tokens: usage[:prompt_tokens], output_tokens: usage[:output_tokens], ts: Time.now.utc.iso8601, timestamp: Time.now.to_i }
        @trace.record(llm_ev)
        append_trace_file(llm_ev)
        [result[:text], usage]
      end

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
