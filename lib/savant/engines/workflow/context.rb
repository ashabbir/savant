#!/usr/bin/env ruby
# frozen_string_literal: true

module Savant
  module Workflow
    # Mutable context storing params and prior step outputs
    class Context
      attr_reader :params, :steps

      def initialize(params: {})
        @params = params || {}
        @steps = {}
      end

      def set(step_name, value)
        @steps[step_name.to_s] = value
      end

      def get(path)
        return nil if path.nil?

        parts = path.to_s.split('.')
        root_key = parts.shift
        obj = case root_key
              when 'params' then @params
              else
                # step name
                @steps[root_key]
              end
        parts.each do |p|
          if obj.is_a?(Hash)
            obj = obj[p] || obj[p.to_sym]
          elsif obj.is_a?(Array)
            idx = begin
              Integer(p)
            rescue StandardError
              nil
            end
            obj = idx ? obj[idx] : nil
          else
            obj = nil
          end
        end
        obj
      end
    end
  end
end
