# frozen_string_literal: true

require 'yaml'

module Savant
  module Logging
    module Audit
      # Loads governance policy (sandbox + audit settings) from config/policy.yml
      # and exposes helpers for middleware to enforce sandboxing and auditing.
      class Policy
        SandboxViolation = Class.new(StandardError)

        DEFAULTS = {
          'sandbox' => false,
          'audit' => {
            'enabled' => false,
            'store' => 'logs/savant_audit.json'
          },
          'replay' => {
            'limit' => 25
          }
        }.freeze

        def self.load(path = default_path)
          data = if path && File.exist?(path)
                   YAML.safe_load(File.read(path), aliases: true) || {}
                 else
                   {}
                 end
          new(data)
        rescue StandardError
          new({})
        end

        def self.default_path
          ENV['SAVANT_POLICY_PATH'] || File.expand_path('../../../../config/policy.yml', __dir__)
        end

        def initialize(config = nil)
          @config = deep_merge(DEFAULTS, config || {})
        end

        def sandbox?
          !!@config['sandbox']
        end

        def audit_enabled?
          !!@config.dig('audit', 'enabled')
        end

        def audit_store_path
          (@config.dig('audit', 'store') || DEFAULTS.dig('audit', 'store')).to_s
        end

        def replay_limit
          limit = @config.dig('replay', 'limit') || DEFAULTS.dig('replay', 'limit')
          limit = limit.to_i
          limit.positive? ? limit : DEFAULTS.dig('replay', 'limit')
        end

        # Enforce sandbox policy for a tool execution.
        # Raises SandboxViolation when sandboxed mode rejects a call.
        def enforce!(tool:, requires_system:, sandbox_override: false)
          return true unless sandbox?
          return true if sandbox_override
          return true unless requires_system

          raise SandboxViolation, "Tool #{tool} blocked by sandbox policy"
        end

        private

        def deep_merge(base, overrides)
          base.merge(overrides || {}) do |_k, old_val, new_val|
            if old_val.is_a?(Hash) && new_val.is_a?(Hash)
              deep_merge(old_val, new_val)
            else
              new_val
            end
          end
        end
      end
    end
  end
end
