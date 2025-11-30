#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'engine'
require_relative '../../framework/mcp/core/dsl'
require_relative '../../framework/mcp/core/validation'

module Savant
  module Workflow
    # MCP tools registrar for the Workflow service
    module Tools
      module_function

      def specs
        build_registrar.specs
      end

      def dispatch(engine, name, args)
        reg = build_registrar(engine)
        reg.call(name, args || {}, ctx: { engine: engine, service: 'workflow' })
      end

      def build_registrar(engine = nil)
        eng = engine || Savant::Workflow::Engine.new
        Savant::Framework::MCP::Core::DSL.build do
          # Input validation
          middleware do |ctx, nm, a, nxt|
            schema = ctx[:schema]
            a2 = begin
              Savant::Framework::MCP::Core::Validation.validate!(schema, a)
            rescue Savant::Framework::MCP::Core::ValidationError => e
              raise "validation error: #{e.message}"
            end
            nxt.call(ctx, nm, a2)
          end

          tool 'workflow_run', description: 'Run a YAML workflow by name (workflows/<name>.yaml)',
                               schema: { type: 'object', properties: { workflow: { type: 'string' }, params: { type: 'object' } }, required: ['workflow'] } do |_ctx, a|
            eng.run(workflow: a['workflow'].to_s, params: a['params'] || {})
          end

          tool 'workflow_runs.list', description: 'List saved workflow runs',
                                     schema: { type: 'object', properties: {} } do |_ctx, _a|
            eng.runs_list
          end

          tool 'workflow_runs.read', description: 'Read a saved workflow run state',
                                     schema: { type: 'object', properties: { workflow: { type: 'string' }, run_id: { type: 'string' } }, required: %w[workflow run_id] } do |_ctx, a|
            eng.run_read(workflow: a['workflow'], run_id: a['run_id'])
          end

          tool 'workflow_runs.delete', description: 'Delete a saved workflow run state',
                                       schema: { type: 'object', properties: { workflow: { type: 'string' }, run_id: { type: 'string' } }, required: %w[workflow run_id] } do |_ctx, a|
            eng.run_delete(workflow: a['workflow'], run_id: a['run_id'])
          end

          tool 'server_info', description: 'Workflow engine info', schema: { type: 'object', properties: {} } do |_ctx, _a|
            eng.server_info
          end

          tool 'workflow.list', description: 'List available YAML workflows',
                                schema: { type: 'object', properties: { filter: { type: 'string' } } } do |_ctx, a|
            eng.workflows_list(filter: a['filter'])
          end
        end
      end
    end
  end
end
