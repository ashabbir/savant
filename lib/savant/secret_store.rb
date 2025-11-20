# frozen_string_literal: true

module Savant
  # Simple in-memory secret store with per-user segregation and sanitization.
  module SecretStore
    module_function

    def reset!
      @store = {}
    end

    def set(user_id, service, key, value)
      (@store ||= {})
      @store[user_id.to_s] ||= {}
      @store[user_id.to_s][service.to_sym] ||= {}
      @store[user_id.to_s][service.to_sym][key.to_sym] = value
    end

    def get(user_id, service, key)
      (@store ||= {})
      @store.dig(user_id.to_s, service.to_sym, key.to_sym)
    end

    # Recursively replace typical secret keys with [REDACTED]
    REDACT_KEYS = %w[token api_token apiKey api_key password secret].freeze

    def sanitize(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(k, v), h|
          key = k.is_a?(Symbol) ? k : k.to_s
          if REDACT_KEYS.include?(key.to_s)
            h[k] = '[REDACTED]'
          else
            h[k] = sanitize(v)
          end
        end
      when Array then obj.map { |e| sanitize(e) }
      else obj
      end
    end
  end
end

