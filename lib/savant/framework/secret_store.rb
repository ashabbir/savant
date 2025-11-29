# frozen_string_literal: true

module Savant
  # Simple in-memory secret store with per-user segregation and sanitization.
  module SecretStore
    module_function

    def reset!
      @store = {}
    end

    def set(user_id, service, key, value)
      @store ||= {}
      @store[user_id.to_s] ||= {}
      @store[user_id.to_s][service.to_sym] ||= {}
      @store[user_id.to_s][service.to_sym][key.to_sym] = value
    end

    def get(user_id, service, key)
      @store ||= {}
      @store.dig(user_id.to_s, service.to_sym, key.to_sym)
    end

    # Return a (shallow) copy of a user's secrets for a service
    def for(user_id, service)
      h = (@store ||= {}).dig(user_id.to_s, service.to_sym)
      h ? deep_dup(h) : nil
    end

    # Load secrets from a YAML file. Supported shapes:
    #
    # users:
    #   alice:
    #     jira:
    #       base_url: https://...
    #       email: alice@example.com
    #       api_token: token123
    #
    # or top-level user ids:
    # alice:
    #   jira:
    #     ...
    def load_file(path)
      data = yaml_safe_read(path)
      users_hash = if data.key?('users')
                     data['users'] || {}
                   else
                     data
                   end
      users_hash.each do |user_id, services|
        next unless services.is_a?(Hash)

        services.each do |svc, entries|
          next unless entries.is_a?(Hash)

          entries.each do |k, v|
            set(user_id, svc, k, v)
          end
        end
      end
      true
    rescue StandardError
      false
    end

    # Recursively replace typical secret keys with [REDACTED]
    REDACT_KEYS = %w[token api_token apiKey api_key password secret].freeze

    def sanitize(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(k, v), h|
          key = k.is_a?(Symbol) ? k : k.to_s
          h[k] = if REDACT_KEYS.include?(key.to_s)
                   '[REDACTED]'
                 else
                   sanitize(v)
                 end
        end
      when Array then obj.map { |e| sanitize(e) }
      else obj
      end
    end

    def yaml_safe_read(path)
      return {} unless path && File.file?(path)

      require 'yaml'
      YAML.safe_load(File.read(path)) || {}
    end

    def deep_dup(obj)
      case obj
      when Hash then obj.transform_values { |v| deep_dup(v) }
      when Array then obj.map { |e| deep_dup(e) }
      else obj
      end
    end
  end
end
