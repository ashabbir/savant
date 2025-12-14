#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require_relative '../../config'

module Savant
  module Framework
    module Engine
      module Config
        # Lightweight loader for framework config with compatibility fallback.
        # - Reads YAML from config/savant.yml when present.
        # - Falls back to existing JSON settings via Savant::Framework::Config.load.
        module Loader
          module_function

          def load(yaml_path: 'config/savant.yml', json_path: 'config/settings.json')
            # Ensure absolute paths by resolving relative to project root
            yaml_path = resolve_path(yaml_path)
            json_path = resolve_path(json_path)

            return safe_yaml(yaml_path) if File.exist?(yaml_path)

            # Fall back to the existing JSON config to preserve current behavior
            Savant::Framework::Config.load(json_path)
          rescue Errno::ENOENT, Savant::ConfigError
            {}
          end

          def resolve_path(path)
            return path if File.absolute_path?(path)

            File.join(project_root, path)
          end

          def project_root
            ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty? ? ENV['SAVANT_PATH'] : File.expand_path('../../../../../', __dir__)
          end

          def safe_yaml(path)
            content = ::YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
            content.is_a?(Hash) ? content : {}
          end
        end
      end
    end
  end
end
