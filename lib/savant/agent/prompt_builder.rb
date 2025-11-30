#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'

module Savant
  module Agent
    # Builds deterministic prompts for SLM/LLM calls.
    class PromptBuilder
      ACTION_SCHEMA_MD = <<~MD
        You MUST output a single JSON object with the following exact schema:
        {
          "action": "tool" | "reason" | "finish" | "error",
          "tool_name": "",
          "args": {},
          "final": "",
          "reasoning": ""
        }
        Return ONLY the JSON. Do not include any prose.
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
      def build(goal:, memory:, last_output: nil, system: nil, tools_hint: nil, tools_catalog: nil)
        persona = @runtime&.persona || {}
        driver = @runtime&.driver_prompt || {}
        amr = @runtime&.amr_rules || {}
        repo = @runtime&.repo

        sections = []
        sections << header_section
        sections << section('Persona', persona[:prompt_md] || persona[:summary])
        sections << section('Driver', driver[:prompt_md])
        sections << section('AMR Rules', summarize_rules(amr[:rules]))
        sections << section('Repo', repo_to_text(repo)) if repo
        sections << section('Goal', goal)
        sections << section('Memory', summarize_memory(memory))
        sections << section('Last Tool Output', last_output) if last_output && !last_output.to_s.empty?
        if tools_hint&.any?
          sections << section('Tools Available', tools_hint.take(150).join("\n"))
          sections << section('Tool Selection Rules',
                              "When action='tool', tool_name MUST be one of the 'Tools Available' list. Use the fully qualified name exactly (slashes '/'). If the goal says 'context.fts.search', choose 'context.fts_search'. NEVER invent or use external tools like 'GitHub CLI', 'curl', 'bash', or 'npm'.")
        end
        sections << section('Tools Catalog', tools_catalog.take(150).join("\n")) if tools_catalog&.any?
        sections << section('System Instructions', system) if system
        sections << section('Action Schema', ACTION_SCHEMA_MD)

        prompt = sections.compact.join("\n\n---\n\n")
        prompt = enforce_budget(prompt)
        trace_prompt(prompt)
        prompt
      end

      private

      def header_section
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
    end
  end
end
