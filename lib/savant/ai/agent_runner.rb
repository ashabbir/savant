#!/usr/bin/env ruby
# frozen_string_literal: true

module Savant
  module AI
    # Minimal sequential agent that executes a plan of tool calls using a provided invoker.
    # Plan format: [{ tool: 'ns/name', args: { ... } }, ...]
    class AgentRunner
      def initialize(invoker:)
        @invoker = invoker
      end

      # Execute steps sequentially, threading a memory hash.
      def run(plan, memory: {})
        results = []
        plan.each_with_index do |step, idx|
          name = step[:tool] || step['tool']
          args = (step[:args] || step['args'] || {}).dup
          args['memory'] = memory if args.key?('use_memory') || args.key?(:use_memory)
          out = @invoker.call(name, args)
          results << { index: idx, tool: name, output: out }
          memory[name] = out
        end
        { results: results, memory: memory }
      end
    end
  end
end

