#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'validation'

module Savant
  module Framework
    module MCP
      module Core
        # Middleware that validates and coerces input using the tool's schema
        # and optionally validates output when an :output_schema is present in ctx.
        class ValidationMiddleware
          def initialize(coerce: true)
            @coerce = coerce
          end

          def call(ctx, name, args, nxt)
            schema = ctx[:schema]
            a2 = @coerce ? Validation.validate!(schema, args) : args
            out = nxt.call(ctx, name, a2)
            if ctx[:output_schema]
              # Best-effort output validation; raise if mismatch
              Validation.validate!(ctx[:output_schema], out)
            end
            out
          rescue ValidationError => e
            raise "validation error: #{e.message}"
          end
        end
      end
    end
  end
end
