#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../version'
require_relative 'ops'

module Savant
  module Drivers
    # Engine exposes drivers catalog (prompt templates) over MCP tools.
    class Engine
      def initialize
        @log = Savant::Logging::MongoLogger.new(service: 'drivers')
        @ops = Savant::Drivers::Ops.new
        # Best-effort migration from Think prompts -> Drivers catalog on first run
        begin
          if @ops.respond_to?(:migrate_from_think_prompts)
            migrated = @ops.migrate_from_think_prompts
            @log.info(event: 'drivers_migration', status: migrated ? 'migrated' : 'skipped')
          end
        rescue StandardError => e
          @log.warn(event: 'drivers_migration_failed', error: e.message)
        end
      end

      def server_info
        { name: 'drivers', version: Savant::VERSION, description: 'Savant Drivers MCP engine (prompt templates)' }
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

      # Per-driver YAML read/write
      def read_yaml(name:)
        @ops.read_driver_yaml(name: name)
      end

      def write_yaml(name:, yaml:)
        @ops.write_driver_yaml(name: name, yaml: yaml)
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
