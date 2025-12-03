#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../version'
require_relative 'ops'

module Savant
  module Rules
    # Engine exposes rule catalog operations for MCP tools.
    class Engine
      def initialize
        @log = Savant::Logging::Logger.new(io: $stdout, json: true, service: 'rules')
        @ops = Savant::Rules::Ops.new
      end

      def server_info
        { name: 'rules', version: Savant::VERSION, description: 'Savant Rules MCP engine' }
      end

      def list(filter: nil)
        @ops.list(filter: filter)
      end

      def get(name:)
        @ops.get(name: name)
      end

      # Raw catalog YAML operations
      def catalog_read
        @ops.catalog_read
      end

      def catalog_write(yaml:)
        @ops.catalog_write(yaml: yaml)
      end

      # Per-rule YAML read/write
      def read_yaml(name:)
        @ops.read_rule_yaml(name: name)
      end

      def write_yaml(name:, yaml:)
        @ops.write_rule_yaml(name: name, yaml: yaml)
      end

      # CRUD for individual rules
      def create(name:, summary:, rules_md:, tags: nil, notes: nil)
        @ops.create(name: name, summary: summary, rules_md: rules_md, tags: tags, notes: notes)
      end

      def update(name:, summary: nil, rules_md: nil, tags: nil, notes: nil)
        @ops.update(name: name, summary: summary, rules_md: rules_md, tags: tags, notes: notes)
      end

      def delete(name:)
        @ops.delete(name: name)
      end
    end
  end
end
