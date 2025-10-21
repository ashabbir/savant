#!/usr/bin/env ruby
# frozen_string_literal: true

module Savant
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
          unless args.is_a?(Hash)
            raise ValidationError, 'invalid arguments: expected object'
          end
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
          if prop[:anyOf]
            # Prefer an alternative whose type matches the raw value
            alts = prop[:anyOf]
            preferred = alts.find { |alt| matches_type?(alt, val) }
            if preferred
              return coerce_value(preferred, val)
            end
            # Fallback: try coercion in order
            alts.each do |alt|
              begin
                return coerce_value(alt, val)
              rescue ValidationError
                next
              end
            end
            raise ValidationError, 'value does not match anyOf'
          end

          case prop[:type]
          when 'string'
            return '' if val.nil?
            return val if val.is_a?(String)
            return val.to_s if val.is_a?(Numeric)
            raise ValidationError, 'expected string'
          when 'integer'
            return Integer(val)
          when 'boolean'
            return true if val == true || (val.is_a?(String) && val.downcase == 'true')
            return false if val == false || (val.is_a?(String) && val.downcase == 'false')
            raise ValidationError, 'invalid boolean'
          when 'array'
            raise ValidationError, 'expected array' unless val.is_a?(Array)
            if prop[:items]&.[](:type) == 'string'
              return val.map { |v| v.to_s }
            end
            return val
          when 'object'
            raise ValidationError, 'expected object' unless val.is_a?(Hash)
            return val
          when nil
            return val
          else
            return val
          end
        rescue ArgumentError
          raise ValidationError, 'invalid integer'
        end

        def matches_type?(prop, val)
          p = symbolize_keys(prop || {})
          case p[:type]
          when 'null' then val.nil?
          when 'string' then val.is_a?(String) || val.is_a?(Numeric)
          when 'integer' then val.is_a?(Integer) || (val.is_a?(String) && val =~ /^\d+$/)
          when 'boolean' then val == true || val == false || (val.is_a?(String) && %w[true false].include?(val.downcase))
          when 'array' then val.is_a?(Array)
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
