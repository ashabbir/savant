# frozen_string_literal: true

# Load .env files manually since Rails 7.2 doesn't do it automatically.
# Preference: repo-root .env first, then server/.env to allow server-specific overrides.
root_env = File.expand_path('../../../.env', __dir__)
server_env = File.expand_path('../../.env', __dir__)

[root_env, server_env].each do |env_file|
  next unless File.exist?(env_file)

  File.readlines(env_file).each do |line|
    line = line.to_s.strip
    next if line.empty? || line.start_with?('#')

    key, value = line.split('=', 2)
    next unless key && value

    ENV[key.strip] = value.strip
  end
end

# Ensure SAVANT_PATH is set to the parent repo root
unless ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
  ENV['SAVANT_PATH'] = File.expand_path('../../..', __dir__)
end

# Ensure the parent repo's lib directory is on the load path
parent_lib = File.expand_path('../../../lib', __dir__)
$LOAD_PATH.unshift(parent_lib) unless $LOAD_PATH.include?(parent_lib)

require 'savant/hub/builder'

module SavantRails
  class SavantContainer
    class << self
      def base_path
        # Parent repo root (Rails app lives in server/)
        File.expand_path('../../..', __dir__)
      end

      # Full Hub Rack app (Router + Static UI) from Savant
      def hub_app
        @hub_app ||= Savant::Hub::Builder.build_from_config(base_path: base_path)
      end

      # Underlying service manager routing inside the Hub app when needed
      def service_manager
        # Obtain the manager through the hub app routes if exposed; otherwise build anew
        @service_manager ||= begin
          Savant::Hub::Builder.build_from_config(base_path: base_path) # returns composed app
        end
      end
    end
  end
end
