#!/usr/bin/env ruby
# frozen_string_literal: true

module Savant
  module MCP
    module Core
      # Simple middleware chain for wrapping tool calls.
      #
      # Purpose: Allow pre/post processing (logging, validation) around calls.
      class MiddlewareChain
        def initialize
          @middlewares = []
        end

        # Each middleware is a proc: ->(ctx, name, args, nxt)
        def use(&blk)
          @middlewares << blk if blk
        end

        def call(ctx, name, args, &final_handler)
          chain = @middlewares.reverse.inject(final_handler) do |nxt, mw|
            proc { |c, nm, a| mw.call(c, nm, a, nxt) }
          end
          chain.call(ctx, name, args)
        end
      end
    end
  end
end
