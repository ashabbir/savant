# frozen_string_literal: true

require 'yaml'
require_relative 'http/router'
require_relative 'transport/base'

module Savant
  # Hub builder: loads engines and returns a Rack app.
  class Hub
    def self.build_from_config(base_path: nil)
      base = base_path || (ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty? ? ENV['SAVANT_PATH'] : File.expand_path('..', __dir__))
      mounts_cfg = safe_load(File.join(base, 'config', 'mounts.yml'))
      transport_cfg = safe_load(File.join(base, 'config', 'transport.yml'))
      # Prefer explicit env, otherwise try repo root secrets.yml then config/secrets.yml
      secrets_path = if ENV['SAVANT_SECRETS_PATH'] && !ENV['SAVANT_SECRETS_PATH'].empty?
                       ENV['SAVANT_SECRETS_PATH']
                     else
                       root_candidate = File.join(base, 'secrets.yml')
                       cfg_candidate = File.join(base, 'config', 'secrets.yml')
                       File.file?(root_candidate) ? root_candidate : cfg_candidate
                     end
      begin
        require_relative 'secret_store'
        Savant::SecretStore.load_file(secrets_path)
      rescue StandardError
        # ignore missing/invalid secrets file
      end

      transport_mode = (transport_cfg.dig('transport', 'mode') || 'http').to_s
      mounts = build_mounts(mounts_cfg)
      Savant::HTTP::Router.build(mounts: mounts, transport: transport_mode)
    end

    def self.build_mounts(cfg)
      entries = (cfg['mounts'] || [])
      entries.each_with_object({}) do |entry, h|
        name = entry['engine']
        next if name.to_s.empty?

        h[name] = Savant::Transport::ServiceManager.new(service: name)
      end
    end

    def self.safe_load(path)
      return {} unless File.file?(path)

      YAML.safe_load(File.read(path)) || {}
    rescue StandardError
      {}
    end
  end
end
