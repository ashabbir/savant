# frozen_string_literal: true

require 'thread'

module Savant
  class Multiplexer
    # Maintains a namespaced view of all engine tools and resolves routes.
    class Router
      def initialize
        @lock = Mutex.new
        @tools = {}
      end

      def register(engine, specs)
        return unless specs

        specs_array = specs.map { |spec| symbolize(spec) }.compact
        @lock.synchronize do
          @tools.delete_if { |_, meta| meta[:engine] == engine }
          specs_array.each do |spec|
            next unless spec[:name]

            fq_name = qualify(engine, spec[:name])
            stored = spec.merge(name: fq_name)
            @tools[fq_name] = { engine: engine, tool: spec[:name], spec: stored }
          end
        end
      end

      def remove(engine)
        @lock.synchronize { @tools.delete_if { |_, meta| meta[:engine] == engine } }
      end

      def tools
        @lock.synchronize { @tools.values.map { |meta| deep_dup(meta[:spec]) } }
      end

      def lookup(name)
        @lock.synchronize { @tools[name] }
      end

      private

      def qualify(engine, tool)
        return tool if tool.to_s.start_with?("#{engine}.")

        "#{engine}.#{tool}"
      end

      def symbolize(spec)
        if spec.respond_to?(:to_h)
          spec.to_h.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
        elsif spec.is_a?(Hash)
          spec.transform_keys(&:to_sym)
        else
          nil
        end
      end

      def deep_dup(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k] = deep_dup(v) }
        when Array
          obj.map { |v| deep_dup(v) }
        else
          obj
        end
      end
    end
  end
end
