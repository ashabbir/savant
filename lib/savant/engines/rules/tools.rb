#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../framework/mcp/core/dsl'
require_relative 'engine'

module Savant
  module Rules
    # Tools registers rule catalog MCP tool definitions.
    module Tools
      module_function

      def build_registrar(engine = nil)
        eng = engine || Savant::Rules::Engine.new
        Savant::Framework::MCP::Core::DSL.build do
          tool 'rules.list',
               description: 'List available rule sets',
               schema: { type: 'object', properties: { filter: { type: 'string' } } } do |_ctx, a|
            eng.list(filter: a['filter'])
          end

          tool 'rules.get',
               description: 'Fetch a ruleset by name',
               schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            eng.get(name: a['name'])
          end

          # Single-rule raw YAML read/write mirroring Think workflows.read/write
          tool 'rules.read',
               description: 'Read a single ruleset YAML by name',
               schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            eng.read_yaml(name: a['name'])
          end

          tool 'rules.write',
               description: 'Overwrite a single ruleset YAML by name',
               schema: { type: 'object', properties: { name: { type: 'string' }, yaml: { type: 'string' } }, required: %w[name yaml] } do |_ctx, a|
            eng.write_yaml(name: a['name'], yaml: a['yaml'] || '')
          end

          # Catalog raw YAML read/write (mirrors Think workflows.read/write)
          tool 'rules.catalog.read',
               description: 'Read the full rules catalog YAML',
               schema: { type: 'object', properties: {} } do |_ctx, _a|
            eng.catalog_read
          end

          tool 'rules.catalog.write',
               description: 'Overwrite the full rules catalog YAML',
               schema: { type: 'object', properties: { yaml: { type: 'string' } }, required: ['yaml'] } do |_ctx, a|
            eng.catalog_write(yaml: a['yaml'] || '')
          end

          # Per-rule CRUD (create/update/delete)
          tool 'rules.create',
               description: 'Create a ruleset entry (version starts at 1)',
               schema: {
                 type: 'object',
                 properties: {
                   name: { type: 'string' },
                   summary: { type: 'string' },
                   rules_md: { type: 'string' },
                   tags: { type: 'array', items: { type: 'string' } },
                   notes: { type: 'string' }
                 },
                 required: %w[name summary rules_md]
               } do |_ctx, a|
            eng.create(name: a['name'], summary: a['summary'], rules_md: a['rules_md'], tags: a['tags'], notes: a['notes'])
          end

          tool 'rules.update',
               description: 'Update a ruleset entry (bumps version by +1)',
               schema: {
                 type: 'object',
                 properties: {
                   name: { type: 'string' },
                   summary: { type: 'string' },
                   rules_md: { type: 'string' },
                   tags: { type: 'array', items: { type: 'string' } },
                   notes: { type: 'string' }
                 },
                 required: %w[name]
               } do |_ctx, a|
            eng.update(name: a['name'], summary: a['summary'], rules_md: a['rules_md'], tags: a['tags'], notes: a['notes'])
          end

          tool 'rules.delete',
               description: 'Delete a ruleset entry by name',
               schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            eng.delete(name: a['name'])
          end
        end
      end
    end
  end
end
