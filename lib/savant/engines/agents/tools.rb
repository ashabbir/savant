#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../framework/mcp/core/dsl'
require_relative 'engine'

module Savant
  module Agents
    # Tools registrar for agents
    module Tools
      module_function

      def build_registrar(engine = nil)
        eng = engine || Savant::Agents::Engine.new
        Savant::Framework::MCP::Core::DSL.build do
          tool 'agents_list', description: 'List agents', schema: { type: 'object', properties: {} } do |_ctx, _a|
            { agents: eng.list }
          end

          tool 'agents_get', description: 'Get an agent by name', schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            eng.get(name: a['name'])
          end

          tool 'agents_create', description: 'Create an agent',
                                  schema: { type: 'object', properties: {
                                    name: { type: 'string' },
                                    persona: { type: 'string' },
                                    driver: { type: 'string' },
                                    rules: { type: 'array', items: { type: 'string' } },
                                    favorite: { type: 'boolean' }
                                  }, required: %w[name persona driver] } do |_ctx, a|
            eng.create(name: a['name'], persona: a['persona'], driver: a['driver'], rules: a['rules'] || [], favorite: a['favorite'] || false)
          end

          tool 'agents_update', description: 'Update an agent (partial)',
                                  schema: { type: 'object', properties: {
                                    name: { type: 'string' },
                                    persona: { type: 'string' },
                                    driver: { type: 'string' },
                                    rules: { type: 'array', items: { type: 'string' } },
                                    favorite: { type: 'boolean' }
                                  }, required: ['name'] } do |_ctx, a|
            eng.update(name: a['name'], persona: a['persona'], driver: a['driver'], rules: a['rules'], favorite: a['favorite'])
          end

          tool 'agents_delete', description: 'Delete an agent', schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            { ok: eng.delete(name: a['name']) }
          end

          tool 'agents_run', description: 'Execute an agent by name',
                               schema: { type: 'object', properties: {
                                 name: { type: 'string' },
                                 input: { type: 'string' },
                                 max_steps: { type: 'integer' },
                                 dry_run: { type: 'boolean' }
                               }, required: %w[name input] } do |_ctx, a|
            eng.run(name: a['name'], input: a['input'], max_steps: a['max_steps'], dry_run: !!a['dry_run'])
          end

          tool 'agents_runs_list', description: 'List recent runs for an agent', schema: { type: 'object', properties: { name: { type: 'string' }, limit: { type: 'integer' } }, required: ['name'] } do |_ctx, a|
            { runs: eng.runs_list(name: a['name'], limit: (a['limit'] || 50)) }
          end

          tool 'agents_run_read', description: 'Read a single run transcript', schema: { type: 'object', properties: { name: { type: 'string' }, run_id: { type: 'integer' } }, required: %w[name run_id] } do |_ctx, a|
            eng.run_read(name: a['name'], run_id: a['run_id'])
          end
        end
      end
    end
  end
end

