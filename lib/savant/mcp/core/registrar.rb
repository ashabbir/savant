#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'tool'
require_relative 'middleware'

module Savant
  module MCP
    module Core
      # Holds and exposes tool specs for MCP discovery and dispatch.
      #
      # Purpose: Provide a small registry abstraction used by service tools.
      class Registrar
        def initialize
          @tools = {}
          @mw = MiddlewareChain.new
        end

        def use_middleware(&)
          @mw.use(&)
        end

        def add_tool(tool)
          raise 'tool name required' if tool.name.to_s.strip.empty?

          @tools[tool.name] = tool
        end

        def specs
          @tools.values.map(&:spec)
        end

        def call(name, args = {}, ctx: {})
          tool = @tools[name]
          raise 'Unknown tool' unless tool

          # Attach tool metadata into ctx for middlewares (e.g., validation).
          # Mutate provided ctx to preserve any bound methods (e.g., ctx.invoke).
          ctx2 = ctx || {}
          ctx2[:tool_name] = tool.name
          ctx2[:schema] = tool.schema
          ctx2[:description] = tool.description
          ctx2[:output_schema] = (tool.respond_to?(:output_schema) ? tool.output_schema : nil)
          @mw.call(ctx2, name, args) do |c, _nm, a|
            tool.handler.call(c, a)
          end
        end
      end
    end
  end
end
