#!/usr/bin/env ruby

require_relative 'tool'
require_relative 'middleware'

module Savant
  module MCP
    module Core
      class Registrar
        def initialize
          @tools = {}
          @mw = MiddlewareChain.new
        end

        def use_middleware(&blk)
          @mw.use(&blk)
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
          @mw.call(ctx, name, args) do |c, _nm, a|
            tool.handler.call(c, a)
          end
        end
      end
    end
  end
end

