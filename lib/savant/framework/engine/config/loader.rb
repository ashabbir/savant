#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require_relative '../../framework/config'

module Savant
  module Core
    module Config
      # Lightweight loader for framework config with compatibility fallback.
      # - Reads YAML from config/savant.yml when present.
      # - Falls back to existing JSON settings via Savant::Framework::Config.load.
      module Loader
        module_function

        def load(yaml_path: 'config/savant.yml', json_path: 'config/settings.json')
          return safe_yaml(yaml_path) if File.exist?(yaml_path)

          # Fall back to the existing JSON config to preserve current behavior
          Savant::Framework::Config.load(json_path)
        rescue Errno::ENOENT
          {}
        end

        def safe_yaml(path)
          content = ::YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
          content.is_a?(Hash) ? content : {}
        end
      end
    end
  end
end
