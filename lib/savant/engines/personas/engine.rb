#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../version'
require_relative 'ops'

module Savant
  module Personas
    # Engine exposes personas catalog over MCP tools.
    class Engine
      def initialize
        @log = Savant::Logging::MongoLogger.new(service: 'personas')
        @ops = Savant::Personas::Ops.new
      end

      def server_info
        { name: 'personas', version: Savant::VERSION, description: 'Savant Personas MCP engine' }
      end

      # API used by Tools
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

      # Per-persona YAML read/write
      def read_yaml(name:)
        @ops.read_persona_yaml(name: name)
      end

      def write_yaml(name:, yaml:)
        @ops.write_persona_yaml(name: name, yaml: yaml)
      end

      # CRUD
      def create(name:, summary:, prompt_md:, tags: nil, notes: nil)
        @ops.create(name: name, summary: summary, prompt_md: prompt_md, tags: tags, notes: notes)
      end

      def update(name:, summary: nil, prompt_md: nil, tags: nil, notes: nil)
        @ops.update(name: name, summary: summary, prompt_md: prompt_md, tags: tags, notes: notes)
      end

      def delete(name:)
        @ops.delete(name: name)
      end
    end
  end
end
