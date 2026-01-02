#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'

module Savant
  module Agent
    # Builds deterministic prompts for SLM/LLM calls.
    class PromptBuilder
      ACTION_SCHEMA_MD = <<~MD
        You are analyzing a task and deciding how to proceed.
        Respond with ONLY these exact lines:
        ACTION: finish
        RESULT: your final answer
        REASONING: short explanation of your decision

        OR

        ACTION: tool_name
        RESULT: tool arguments (query or JQL)
        REASONING: why you need this tool
      MD

      def initialize(runtime:, logger: nil)
        @runtime = runtime
        @logger = logger || runtime&.logger
        @slm_budget = (ENV['SLM_BUDGET_TOKENS'] || '8000').to_i
      end

      # Build prompt string with deterministic sections.
      # Inputs
      # - goal [String]
      # - memory [Hash]
      # - last_output [String,nil]
      # - system [String,nil]
      # - tools_hint [Array<String>,nil]
      def build(goal:, memory:, last_output: nil, system: nil, tools_hint: nil, tools_catalog: nil, agent_instructions: nil, agent_rulesets: nil, agent_state: nil)
        persona = @runtime&.persona || {}
        driver = @runtime&.driver_prompt || {}
        amr = @runtime&.amr_rules || {}
        repo = @runtime&.repo

        sections = []
        sections << header_section(tools_hint, tools_catalog)
        sections << section('Persona', persona[:prompt_md] || persona[:summary])
        sections << section('Driver', driver[:prompt_md])
        sections << section('Agent Instructions', agent_instructions)
        sections << section('Agent Rulesets', summarize_rulesets(agent_rulesets))
        sections << section('AMR Rules', summarize_rules(amr[:rules]))
        sections << section('Repo', repo_to_text(repo)) if repo
        sections << section('Goal', goal)
        sections << section('Memory', summarize_memory(memory))
        sections << section('Last Tool Output', last_output) if last_output && !last_output.to_s.empty?
        if tools_hint&.any?
          sections << section('Tools Available', tools_hint.take(150).join("\n"))
          sections << section('Tool Selection Rules',
                              "When action='tool', tool_name MUST be one of the 'Tools Available' list. Use the fully qualified name exactly (e.g., 'context.fts_search'). NEVER invent or use external tools like 'GitHub CLI', 'curl', 'bash', or 'npm'.")
        end
        sections << section('Tools Catalog', tools_catalog.take(150).join("\n")) if tools_catalog&.any?
        sections << section('Agent State', summarize_state(agent_state)) if agent_state
        sections << section('System Instructions', system) if system
        sections << section('Action Schema', ACTION_SCHEMA_MD)

        prompt = sections.compact.join("\n\n---\n\n")
        prompt = enforce_budget(prompt)
        trace_prompt(prompt)
        prompt
      end

      private

      def header_section(tools_hint, tools_catalog)
        has_tools = tools_hint&.any? || tools_catalog&.any?
        return 'You are Savant Agent Runtime. Answer the goal directly without tools. Always return the required JSON envelope.' unless has_tools

        'You are Savant Agent Runtime. Plan tool calls to accomplish the goal. Always return the required JSON envelope.'
      end

      def section(title, body)
        return nil if body.nil? || body.to_s.strip.empty?

        "## #{title}\n#{body.to_s.strip}"
      end

      def summarize_rules(rules)
        return '' unless rules.is_a?(Array)

        rules.first(10).map { |r| "- #{r['id'] || r[:id]} (#{r['priority'] || r[:priority] || 'n/a'})" }.join("\n")
      end

      def summarize_rulesets(rulesets)
        return '' unless rulesets.is_a?(Array)

        # Prefer explicit rules_md from rulesets; fall back to summary/name.
        lines = rulesets.first(10).map do |r|
          name = (r['name'] || r[:name] || 'ruleset').to_s
          text = (r['rules_md'] || r[:rules_md] || r['summary'] || r[:summary] || '').to_s
          next nil if text.strip.empty?

          "- #{name}: #{text.strip}"
        end.compact
        return '' if lines.empty?

        lines.join("\n")
      end

      def repo_to_text(repo)
        return '' unless repo

        "path: #{repo[:path]}\nbranch: #{repo[:branch]}"
      end

      def summarize_memory(memory)
        return 'empty' unless memory.is_a?(Hash)

        steps = memory[:steps] || []
        errs = memory[:errors] || []
        [
          "steps: #{steps.size}",
          (errs.any? ? "errors: #{errs.size}" : nil)
        ].compact.join(', ')
      end

      def enforce_budget(text)
        # Very rough token estimator: chars/4
        est_tokens = (text.length / 4.0).ceil
        return text if est_tokens <= @slm_budget

        # Trim from the top by removing earlier sections except schema & goal
        lines = text.split("\n")
        # Keep last N lines to fit budget (greedy)
        keep_ratio = (@slm_budget / est_tokens.to_f)
        keep_count = [(lines.size * keep_ratio).floor, lines.size].min
        trimmed = lines.last(keep_count).join("\n")
        return trimmed if (trimmed.length / 4.0) <= @slm_budget

        # As a last resort, keep only goal + schema
        if text[/## Goal[\s\S]*?(?=##|\z)/] && text[/## Action Schema[\s\S]*\z/]
          [text[/## Goal[\s\S]*?(?=##|\z)/].to_s, text[/## Action Schema[\s\S]*\z/].to_s].join("\n\n---\n\n")
        else
          text
        end
      end

      def trace_prompt(prompt)
        @logger&.trace(event: 'agent_prompt', size: prompt.length, hash: Digest::SHA256.hexdigest(prompt)[0, 16])
      rescue StandardError
        # no-op if digest not available
      end

      def summarize_state(state)
        return nil unless state.is_a?(Hash)

        lines = []
        lines << "Current Phase: #{state[:current_state].to_s.upcase}"
        lines << "Phase Duration: #{state[:duration_ms]}ms"
        lines << "Status: #{state[:stuck] ? 'STUCK' : 'HEALTHY'}"
        lines << "Advice: #{state[:suggested_exit]}" if state[:suggested_exit]
        lines.join("\n")
      end
    end
  end
end
