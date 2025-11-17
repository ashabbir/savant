#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'engine'
require_relative '../mcp/core/dsl'
require_relative '../mcp/core/validation'

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
        Savant::MCP::Core::DSL.build do
          # Validation middleware
          middleware do |ctx, name, a, nxt|
            schema = ctx[:schema]
            a2 = begin
              Savant::MCP::Core::Validation.validate!(schema, a)
            rescue Savant::MCP::Core::ValidationError => e
              raise "validation error: #{e.message}"
            end
            nxt.call(ctx, name, a2)
          end

          tool 'think.driver_prompt', description: 'Return versioned driver prompt markdown',
                                      schema: { type: 'object', properties: { version: { type: 'string' } } } do |_ctx, a|
            eng.driver_prompt(version: a['version'])
          end

          tool 'think.plan', description: 'Initialize a workflow run and return first instruction',
                             schema: { type: 'object', properties: { workflow: { type: 'string' }, params: { type: 'object' } }, required: ['workflow'] } do |_ctx, a|
            eng.plan(workflow: a['workflow'].to_s, params: a['params'] || {})
          end

          tool 'think.next', description: 'Advance a workflow by recording step result and returning next instruction',
                             schema: { type: 'object', properties: { workflow: { type: 'string' }, step_id: { type: 'string' }, result_snapshot: { type: 'object' } }, required: %w[workflow step_id] } do |_ctx, a|
            eng.next(workflow: a['workflow'].to_s, step_id: a['step_id'].to_s, result_snapshot: a['result_snapshot'] || {})
          end

          tool 'think.workflows.list', description: 'List available workflows',
                                       schema: { type: 'object', properties: { filter: { type: 'string' } } } do |_ctx, a|
            eng.workflows_list(filter: a['filter'])
          end

          tool 'think.workflows.read', description: 'Read raw workflow YAML',
                                       schema: { type: 'object', properties: { workflow: { type: 'string' } }, required: ['workflow'] } do |_ctx, a|
            eng.workflows_read(workflow: a['workflow'])
          end

          tool 'prompt.say', description: 'Display a message to the LLM/user (no-op for engine)',
                             schema: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'] } do |_ctx, a|
            { message: a['text'].to_s, display: true, timestamp: Time.now.utc.iso8601 }
          end

          # NOTE: Think does not re‑expose Context FTS or local FS search.
          # The Instruction Engine should guide the LLM to call Context MCP tools
          # (e.g., 'fts/search') and perform local workspace searches using its
          # editor capabilities.

          # THINK NOTE: Think does not run rubocop/rspec itself. For quality gates,
          # the instruction will ask the LLM to run local commands step-by-step.
        end
      end
    end
  end
end
