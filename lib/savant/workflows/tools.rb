#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'engine'
require_relative '../mcp/core/dsl'
require_relative '../mcp/core/validation'

module Savant
  module Workflows
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
        eng = engine || Savant::Workflows::Engine.new
        Savant::MCP::Core::DSL.build do
          # Validation middleware (JSON schema – permissive for now)
          middleware do |ctx, name, a, nxt|
            a2 = a || {}
            nxt.call(ctx, name, a2)
          rescue Savant::MCP::Core::ValidationError => e
            raise "validation error: #{e.message}"
          end

          tool 'workflows.list', description: 'List workflow metadata', schema: { type: 'object', properties: {} } do |_ctx, _a|
            eng.list
          end

          tool 'workflows.read', description: 'Read workflow YAML + graph',
                                 schema: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] } do |_ctx, a|
            eng.read(id: a['id'])
          end

          tool 'workflows.validate', description: 'Validate workflow graph without saving',
                                     schema: { type: 'object', properties: { graph: { type: 'object' } }, required: ['graph'] } do |_ctx, a|
            eng.validate(graph: a['graph'] || {})
          end

          tool 'workflows.create', description: 'Create workflow from graph',
                                   schema: { type: 'object', properties: { id: { type: 'string' }, graph: { type: 'object' } }, required: %w[id graph] } do |_ctx, a|
            eng.create(id: a['id'], graph: a['graph'] || {})
          end

          tool 'workflows.update', description: 'Update workflow from graph',
                                   schema: { type: 'object', properties: { id: { type: 'string' }, graph: { type: 'object' } }, required: %w[id graph] } do |_ctx, a|
            eng.update(id: a['id'], graph: a['graph'] || {})
          end

          tool 'workflows.delete', description: 'Delete workflow by id',
                                   schema: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] } do |_ctx, a|
            eng.delete(id: a['id'])
          end
        end
      end
    end
  end
end
