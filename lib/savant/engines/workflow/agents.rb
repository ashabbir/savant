#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

module Savant
  module Workflow
    # Simple adapters for known agents. Defaults to deterministic stubs unless WORKFLOW_AGENT_REAL=1
    module Agents
      module_function

      def run(name, with)
        real = ENV['WORKFLOW_AGENT_REAL'] == '1'
        case name.to_s
        when 'summarizer'
          return stub('summarizer', with) unless real

          goal = build_summarizer_goal(with)
          run_agent(goal)
        when 'mr_review'
          return stub_mr_review(with) unless real

          goal = build_mr_review_goal(with)
          res = run_agent(goal)
          enrich_mr_review_output(res)
        else
          return stub(name, with) unless real

          goal = (with.is_a?(Hash) && with['goal'].is_a?(String) ? with['goal'] : "Run agent '#{name}' with inputs: #{JSON.generate(with)}")
          run_agent(goal)
        end
      end

      def stub(name, with)
        {
          status: 'ok',
          agent: name.to_s,
          mode: 'stub',
          inputs_summary: summarize(with),
          final: "[stub] #{name} completed",
          steps: 0
        }
      end

      def summarize(obj)
        case obj
        when String then { type: 'string', bytes: obj.bytesize, preview: obj.byteslice(0, 120) }
        when Array then { type: 'array', length: obj.length }
        when Hash then { type: 'object', keys: obj.keys.take(20), key_count: obj.keys.length }
        else { type: obj.class.name }
        end
      end

      def run_agent(goal)
        require_relative '../../agent/runtime'
        agent = Savant::Agent::Runtime.new(goal: goal)
        agent.run(max_steps: 5, dry_run: false)
      end

      def build_summarizer_goal(with)
        target = with['text'] || with['review'] || with['input'] || with
        "Summarize the following content for a human reader. Return a short, clear summary.\nINPUT:\n#{JSON.pretty_generate(target)}"
      end

      def build_mr_review_goal(with)
        diff = with['diff'] || with['changes'] || {}
        ctx = with['cross_repo'] || with['context'] || {}
        hints = with['hints']
        <<~MD
          Perform a code review for the following MR diff. Identify risks, architecture issues, tests affected, and suggest focused changes. Be concise.
          #{hints ? "Hints: #{hints}\n" : ''}
          DIFF:
          #{JSON.pretty_generate(diff)}
          CROSS-REPO CONTEXT:
          #{JSON.pretty_generate(ctx)}
        MD
      end
    end
  end
end

def stub_mr_review(with)
  base = stub('mr_review', with)
  base.merge(
    findings: ['Identify high-risk files', 'Check DB migrations', 'Verify API contract changes'],
    risks: ['Potential N+1 in list endpoint', 'Missing null checks on user inputs'],
    tests: ['Update unit tests for service A', 'Add integration test for endpoint X'],
    checklist: ['Run rubocop', 'Run rspec', 'Update README if API changed']
  )
end

# Best-effort enrichment: extract structured arrays from final markdown
def enrich_mr_review_output(res)
  out = res.is_a?(Hash) ? res.dup : { raw: res }
  text = (out['final'] || out[:final] || '').to_s
  return out if text.empty?

  sections = parse_markdown_sections(text)
  out['findings'] ||= sections['findings'] unless sections['findings'].empty?
  out['risks'] ||= sections['risks'] unless sections['risks'].empty?
  out['tests'] ||= sections['tests'] unless sections['tests'].empty?
  out['checklist'] ||= sections['checklist'] unless sections['checklist'].empty?
  out
rescue StandardError
  out
end

def parse_markdown_sections(md)
  # Normalize newlines and headings
  txt = md.to_s.gsub("\r\n", "\n")
  buckets = { 'findings' => [], 'risks' => [], 'tests' => [], 'checklist' => [] }
  current = nil
  txt.split("\n").each do |ln|
    if ln =~ /^\s{0,3}#+\s*(.+?)\s*$/
      h = Regexp.last_match(1).downcase
      current = case h
                when /finding|observation|note/ then 'findings'
                when /risk|concern|issue/ then 'risks'
                when /test/ then 'tests'
                when /checklist|action|todo/ then 'checklist'
                end
      next
    end
    next unless ln =~ /^\s*[-*+]\s+(.+)$/

    item = Regexp.last_match(1).strip
    if current
      buckets[current] << item
    else
      # no current section; heuristically drop into findings
      buckets['findings'] << item
    end
  end
  buckets
end
