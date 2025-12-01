#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'

module Savant
  module Workflow
    # Loads YAML workflows from root workflows/ dir
    class Loader
      class LoadError < StandardError; end

      def self.load(base_path, id)
        new(base_path: base_path).load(id)
      end

      def initialize(base_path: nil)
        @base_path = base_path || default_base_path
      end

      def load(id)
        path = File.join(@base_path, 'workflows', "#{id}.yaml")
        raise LoadError, "workflow not found: #{id}" unless File.file?(path)
        data = YAML.safe_load(File.read(path), permitted_classes: [], aliases: true)
        raise LoadError, 'invalid workflow: expected mapping' unless data.is_a?(Hash)
        steps = Array(data['steps']).map do |s|
          raise LoadError, 'each step must be a mapping' unless s.is_a?(Hash)
          name = (s['name'] || '').to_s
          raise LoadError, 'step.name missing' if name.empty?
          type = if s['tool']
                   :tool
                 elsif s['agent']
                   :agent
                 else
                   raise LoadError, "step #{name} missing tool/agent"
                 end
          {
            name: name,
            type: type,
            ref: (s['tool'] || s['agent']).to_s,
            with: (s['with'] || {})
          }
        end
        { id: id, steps: steps }
      rescue Psych::SyntaxError => e
        raise LoadError, e.message
      end

      private

      def default_base_path
        if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
          ENV['SAVANT_PATH']
        else
          File.expand_path('../../../../..', __dir__)
        end
      end
    end
  end
end

