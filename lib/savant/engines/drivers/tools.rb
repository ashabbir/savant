#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../framework/mcp/core/dsl'
require_relative 'engine'

module Savant
  module Drivers
    # Tools registers drivers MCP tool specs.
    module Tools
      module_function

      def build_registrar(engine = nil)
        eng = engine || Savant::Drivers::Engine.new
        Savant::Framework::MCP::Core::DSL.build do
          # drivers_list
          tool 'drivers_list', description: 'List available drivers',
                               schema: { type: 'object', properties: { filter: { type: 'string' } } } do |_ctx, a|
            eng.list(filter: a['filter'])
          end

          # drivers_get
          tool 'drivers_get', description: 'Fetch a driver by name',
                              schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            eng.get(name: a['name'])
          end

          # Single driver raw YAML read/write
          tool 'drivers_read',
               description: 'Read a single driver YAML by name',
               schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            eng.read_yaml(name: a['name'])
          end

          tool 'drivers_write',
               description: 'Overwrite a single driver YAML by name',
               schema: { type: 'object', properties: { name: { type: 'string' }, yaml: { type: 'string' } }, required: %w[name yaml] } do |_ctx, a|
            eng.write_yaml(name: a['name'], yaml: a['yaml'] || '')
          end

          # Catalog read/write
          tool 'drivers_catalog_read',
               description: 'Read the full drivers catalog YAML',
               schema: { type: 'object', properties: {} } do |_ctx, _a|
            eng.catalog_read
          end

          tool 'drivers_catalog_write',
               description: 'Overwrite the full drivers catalog YAML',
               schema: { type: 'object', properties: { yaml: { type: 'string' } }, required: ['yaml'] } do |_ctx, a|
            eng.catalog_write(yaml: a['yaml'] || '')
          end

          # CRUD for drivers
          tool 'drivers_create',
               description: 'Create a driver entry (version starts at 1)',
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

          tool 'drivers_update',
               description: 'Update a driver entry (bumps version by +1)',
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

          tool 'drivers_delete',
               description: 'Delete a driver entry by name',
               schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            eng.delete(name: a['name'])
          end
        end
      end
    end
  end
end
