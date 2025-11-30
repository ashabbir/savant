#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../framework/mcp/core/dsl'
require_relative 'engine'

module Savant
  module Personas
    # Tools registers personas MCP tool specs.
    module Tools
      module_function

      def build_registrar(engine = nil)
        eng = engine || Savant::Personas::Engine.new
        Savant::Framework::MCP::Core::DSL.build do
          # personas.list
          tool 'personas_list', description: 'List available personas',
                                schema: { type: 'object', properties: { filter: { type: 'string' } } } do |_ctx, a|
            eng.list(filter: a['filter'])
          end

          # personas.get
          tool 'personas_get', description: 'Fetch a persona by name',
                               schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            eng.get(name: a['name'])
          end

          # Single persona raw YAML read/write
          tool 'personas_read',
               description: 'Read a single persona YAML by name',
               schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            eng.read_yaml(name: a['name'])
          end

          tool 'personas_write',
               description: 'Overwrite a single persona YAML by name',
               schema: { type: 'object', properties: { name: { type: 'string' }, yaml: { type: 'string' } }, required: %w[name yaml] } do |_ctx, a|
            eng.write_yaml(name: a['name'], yaml: a['yaml'] || '')
          end

          # Catalog read/write
          tool 'personas_catalog_read',
               description: 'Read the full personas catalog YAML',
               schema: { type: 'object', properties: {} } do |_ctx, _a|
            eng.catalog_read
          end

          tool 'personas_catalog_write',
               description: 'Overwrite the full personas catalog YAML',
               schema: { type: 'object', properties: { yaml: { type: 'string' } }, required: ['yaml'] } do |_ctx, a|
            eng.catalog_write(yaml: a['yaml'] || '')
          end

          # CRUD for personas
          tool 'personas_create',
               description: 'Create a persona entry (version starts at 1)',
               schema: {
                 type: 'object',
                 properties: {
                   name: { type: 'string' },
                   summary: { type: 'string' },
                   prompt_md: { type: 'string' },
                   tags: { type: 'array', items: { type: 'string' } },
                   notes: { type: 'string' }
                 },
                 required: %w[name summary prompt_md]
               } do |_ctx, a|
            eng.create(name: a['name'], summary: a['summary'], prompt_md: a['prompt_md'], tags: a['tags'], notes: a['notes'])
          end

          tool 'personas_update',
               description: 'Update a persona entry (bumps version by +1)',
               schema: {
                 type: 'object',
                 properties: {
                   name: { type: 'string' },
                   summary: { type: 'string' },
                   prompt_md: { type: 'string' },
                   tags: { type: 'array', items: { type: 'string' } },
                   notes: { type: 'string' }
                 },
                 required: %w[name]
               } do |_ctx, a|
            eng.update(name: a['name'], summary: a['summary'], prompt_md: a['prompt_md'], tags: a['tags'], notes: a['notes'])
          end

          tool 'personas_delete',
               description: 'Delete a persona entry by name',
               schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            eng.delete(name: a['name'])
          end
        end
      end
    end
  end
end
