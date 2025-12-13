#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'engine'
require_relative '../../framework/mcp/core/dsl'
require_relative '../../framework/mcp/core/validation'

module Savant
  module Think
    # MCP tools registrar for the Think service.
    module Tools
      module_function

      def specs
        build_registrar.specs
      end

      def dispatch(engine, name, args)
        reg = build_registrar(engine)
        reg.call(name, args || {}, ctx: { engine: engine })
      end

      def build_registrar(engine = nil)
        eng = engine || Savant::Think::Engine.new
        Savant::Framework::MCP::Core::DSL.build do
          # Validation middleware
          middleware do |ctx, name, a, nxt|
            schema = ctx[:schema]
            a2 = begin
              Savant::Framework::MCP::Core::Validation.validate!(schema, a)
            rescue Savant::Framework::MCP::Core::ValidationError => e
              raise "validation error: #{e.message}"
            end
            nxt.call(ctx, name, a2)
          end

          # NOTE: Driver prompts have moved to the Drivers engine (drivers_get, drivers_list).
          # Workflows should explicitly include a step that calls drivers_get if they need
          # a driver prompt.

          tool 'think_plan', description: 'Initialize a workflow run and return first instruction',
                             schema: { type: 'object', properties: { workflow: { type: 'string' }, params: { type: 'object' }, run_id: { type: 'string' }, start_fresh: { type: 'boolean' } }, required: ['workflow'] } do |_ctx, a|
            start_fresh = a.key?('start_fresh') ? !a['start_fresh'].nil? : true
            eng.plan(workflow: a['workflow'].to_s, params: a['params'] || {}, run_id: a['run_id'], start_fresh: start_fresh)
          end

          tool 'think_next', description: 'Advance a workflow by recording step result and returning next instruction',
                             schema: { type: 'object', properties: { workflow: { type: 'string' }, run_id: { type: 'string' }, step_id: { type: 'string' }, result_snapshot: { type: 'object' } }, required: %w[workflow run_id step_id] } do |_ctx, a|
            eng.next(workflow: a['workflow'].to_s, run_id: a['run_id'].to_s, step_id: a['step_id'].to_s, result_snapshot: a['result_snapshot'] || {})
          end

          tool 'think_workflows_list', description: 'List available workflows',
                                       schema: { type: 'object', properties: { filter: { type: 'string' } } } do |_ctx, a|
            eng.workflows_list(filter: a['filter'])
          end

          tool 'think_workflows_read', description: 'Read raw workflow YAML',
                                       schema: { type: 'object', properties: { workflow: { type: 'string' } }, required: ['workflow'] } do |_ctx, a|
            eng.workflows_read(workflow: a['workflow'])
          end

          tool 'think_workflows_graph', description: 'Return nodes and topological order for a workflow',
                                        schema: { type: 'object', properties: { workflow: { type: 'string' } }, required: ['workflow'] } do |_ctx, a|
            eng.workflows_graph(workflow: a['workflow'])
          end

          # CRUD + validation for Think workflows
          tool 'think_workflows_validate', description: 'Validate Think workflow graph',
                                           schema: { type: 'object', properties: { graph: { type: 'object' } }, required: ['graph'] } do |_ctx, a|
            eng.workflows_validate_graph(graph: a['graph'] || {})
          end

          tool 'think_workflows_create', description: 'Create Think workflow from graph',
                                         schema: { type: 'object', properties: { workflow: { type: 'string' }, graph: { type: 'object' } }, required: %w[workflow graph] } do |_ctx, a|
            eng.workflows_create_from_graph(workflow: a['workflow'], graph: a['graph'] || {})
          end

          tool 'think_workflows_update', description: 'Update Think workflow from graph',
                                         schema: { type: 'object', properties: { workflow: { type: 'string' }, graph: { type: 'object' } }, required: %w[workflow graph] } do |_ctx, a|
            eng.workflows_update_from_graph(workflow: a['workflow'], graph: a['graph'] || {})
          end

          tool 'think_workflows_write', description: 'Overwrite workflow YAML',
                                        schema: { type: 'object', properties: { workflow: { type: 'string' }, yaml: { type: 'string' } }, required: %w[workflow yaml] } do |_ctx, a|
            eng.workflows_write_yaml(workflow: a['workflow'], yaml: a['yaml'] || '')
          end

          tool 'think_workflows_delete', description: 'Delete a Think workflow YAML',
                                         schema: { type: 'object', properties: { workflow: { type: 'string' } }, required: %w[workflow] } do |_ctx, a|
            eng.workflows_delete(workflow: a['workflow'])
          end

          tool 'think_say', description: 'Output a message during workflow execution',
                            schema: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'] } do |_ctx, a|
            { message: a['text'].to_s, timestamp: Time.now.utc.iso8601 }
          end

          tool 'think_limits_read', description: 'Read Think engine limits/config',
                                    schema: { type: 'object', properties: {} } do |_ctx, _a|
            eng.limits
          end

          tool 'think_runs_list', description: 'List saved Think workflow runs',
                                  schema: { type: 'object', properties: {} } do |_ctx, _a|
            eng.runs_list
          end

          tool 'think_runs_read', description: 'Read a Think run state',
                                  schema: { type: 'object', properties: { workflow: { type: 'string' }, run_id: { type: 'string' } }, required: %w[workflow run_id] } do |_ctx, a|
            eng.run_read(workflow: a['workflow'], run_id: a['run_id'])
          end

          tool 'think_runs_delete', description: 'Delete a Think run state',
                                    schema: { type: 'object', properties: { workflow: { type: 'string' }, run_id: { type: 'string' } }, required: %w[workflow run_id] } do |_ctx, a|
            eng.run_delete(workflow: a['workflow'], run_id: a['run_id'])
          end

          # NOTE: Think does not re‑expose Context FTS or local FS search.
          # The Instruction Engine should guide the LLM to call Context MCP tools
          # (e.g., 'fts_search') and perform local workspace searches using its
          # editor capabilities.

          # THINK NOTE: Think does not run rubocop/rspec itself. For quality gates,
          # the instruction will ask the LLM to run local commands step-by-step.
        end
      end
    end
  end
end
