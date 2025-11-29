#!/usr/bin/env ruby
# frozen_string_literal: true

module Savant
  module Framework
    module MCP
      module Core
        # Error raised when MCP tool arg validation fails.
        #
        # Purpose: Provide a specific error class for coherent error handling.
        class ValidationError < StandardError; end

        # Schema validation and basic coercion for tool inputs.
        module Validation
        module_function

        def validate!(schema, args)
          args ||= {}
          raise ValidationError, 'invalid arguments: expected object' unless args.is_a?(Hash)

          sch = symbolize_keys(schema || {})
          props = symbolize_keys(sch[:properties] || {})
          required = Array(sch[:required] || []).map(&:to_s)

          # required keys
          required.each do |k|
            raise ValidationError, "missing required: #{k}" unless args.key?(k) && !args[k].nil?
          end

          coerced = args.dup
          props.each do |name, prop|
            next unless coerced.key?(name.to_s)

            val = coerced[name.to_s]
            coerced[name.to_s] = coerce_value(prop, val)
          end
          coerced
        end

        def coerce_value(prop, val)
          prop = symbolize_keys(prop || {})
          return coerce_any_of(prop[:anyOf], val) if prop[:anyOf]

          case prop[:type]
          when 'string'  then coerce_string(val)
          when 'integer' then coerce_integer(val)
          when 'boolean' then coerce_boolean(val)
          when 'array'   then coerce_array(val, prop)
          when 'object'  then coerce_object(val)
          when 'null', nil then val
          else val
          end
        end

        def coerce_any_of(alts, val)
          preferred = alts.find { |alt| matches_type?(alt, val) }
          return coerce_value(preferred, val) if preferred

          alts.each do |alt|
            return coerce_value(alt, val)
          rescue ValidationError
            next
          end
          raise ValidationError, 'value does not match anyOf'
        end

        def coerce_string(val)
          return '' if val.nil?
          return val if val.is_a?(String)
          return val.to_s if val.is_a?(Numeric)

          raise ValidationError, 'expected string'
        end

        def coerce_integer(val)
          # Treat nil/empty as missing so callers can apply defaults.
          return nil if val.nil? || (val.is_a?(String) && val.strip.empty?)

          Integer(val)
        rescue ArgumentError, TypeError
          raise ValidationError, 'invalid integer'
        end

        def coerce_boolean(val)
          # Treat nil as missing so callers can apply defaults.
          return nil if val.nil?

          return true if val == true || (val.is_a?(String) && val.downcase == 'true')
          return false if val == false || (val.is_a?(String) && val.downcase == 'false')

          raise ValidationError, 'invalid boolean'
        end

        def coerce_array(val, prop)
          raise ValidationError, 'expected array' unless val.is_a?(Array)
          return val.map(&:to_s) if prop[:items]&.[](:type) == 'string'

          val
        end

        def coerce_object(val)
          raise ValidationError, 'expected object' unless val.is_a?(Hash)

          val
        end

        def matches_type?(prop, val)
          p = symbolize_keys(prop || {})
          case p[:type]
          when 'null'   then val.nil?
          when 'string' then val.is_a?(String) || val.is_a?(Numeric)
          when 'integer' then val.is_a?(Integer) || (val.is_a?(String) && val =~ /^\d+$/)
          when 'boolean' then (val == true) || (val == false) || (val.is_a?(String) && %w[true
                                                                                          false].include?(val.downcase))
          when 'array'  then val.is_a?(Array)
          when 'object' then val.is_a?(Hash)
          else true
          end
        end

        def symbolize_keys(obj)
          case obj
          when Hash
            obj.each_with_object({}) { |(k, v), h| h[k.to_sym] = symbolize_keys(v) }
          when Array
            obj.map { |e| symbolize_keys(e) }
          else
            obj
          end
        end
        end
      end
    end
  end
end
