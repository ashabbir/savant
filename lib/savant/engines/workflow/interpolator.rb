#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

module Savant
  module Workflow
    # Performs {{ path.to.value }} interpolation recursively
    class Interpolator
      PLACEHOLDER = /\{\{\s*([^}]+?)\s*\}\}/.freeze

      def initialize(context)
        @ctx = context
      end

      def apply(obj)
        case obj
        when String
          interpolate_string(obj)
        when Array
          obj.map { |el| apply(el) }
        when Hash
          obj.each_with_object({}) do |(k, v), h|
            h[k] = apply(v)
          end
        else
          obj
        end
      end

      private

      def interpolate_string(str)
        str.gsub(PLACEHOLDER) do
          path = Regexp.last_match(1).to_s.strip
          val = @ctx.get(path)
          case val
          when NilClass
            ''
          when String, Numeric, TrueClass, FalseClass
            val.to_s
          else
            # Non-scalar types get JSON stringified
            JSON.generate(val)
          end
        end
      end
    end
  end
end
