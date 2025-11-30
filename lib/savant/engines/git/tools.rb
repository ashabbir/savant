#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'engine'
require_relative '../../framework/mcp/core/dsl'
require_relative '../../framework/mcp/core/validation'

module Savant
  module Git
    # MCP tools registrar for the Git service.
    # Provides tool specs and dispatches invocations to the Git engine.
    module Tools
      module_function

      def specs
        build_registrar.specs
      end

      def dispatch(engine, name, args)
        reg = build_registrar(engine)
        reg.call(name, args || {}, ctx: { engine: engine, service: 'git' })
      end

      def build_registrar(engine = nil)
        Savant::Framework::MCP::Core::DSL.build do
          # Validation middleware using tool schema
          middleware do |ctx, nm, a, nxt|
            schema = ctx[:schema]
            a2 = begin
              Savant::Framework::MCP::Core::Validation.validate!(schema, a)
            rescue Savant::Framework::MCP::Core::ValidationError => e
              raise "validation error: #{e.message}"
            end
            nxt.call(ctx, nm, a2)
          end

          tool 'repo_status', description: 'Detect repo root, branch, HEAD and tracked files',
                              schema: { type: 'object', properties: { path: { type: 'string' } } } do |_ctx, a|
            (engine || Savant::Git::Engine.new).repo_status(path: a['path'])
          end

          tool 'changed_files', description: 'List changed files with status (working tree or staged with --staged)',
                                schema: { type: 'object', properties: { staged: { type: 'boolean' }, path: { type: 'string' } } } do |_ctx, a|
            (engine || Savant::Git::Engine.new).changed_files(staged: !!a['staged'], path: a['path'])
          end

          tool 'diff', description: 'Structured unified diff per file (hunks and lines)',
                       schema: { type: 'object', properties: { staged: { type: 'boolean' }, paths: { type: 'array', items: { type: 'string' } } } } do |_ctx, a|
            (engine || Savant::Git::Engine.new).diff(staged: !!a['staged'], paths: a['paths'])
          end

          tool 'hunks', description: 'Structured hunk extraction (added/removed line numbers)',
                        schema: { type: 'object', properties: { staged: { type: 'boolean' }, paths: { type: 'array', items: { type: 'string' } } } } do |_ctx, a|
            (engine || Savant::Git::Engine.new).hunks(staged: !!a['staged'], paths: a['paths'])
          end

          tool 'read_file', description: 'Read file from worktree or HEAD',
                            schema: {
                              type: 'object',
                              properties: {
                                path: { type: 'string' },
                                at: { type: 'string', enum: %w[worktree HEAD] }
                              },
                              required: ['path']
                            } do |_ctx, a|
            (engine || Savant::Git::Engine.new).read_file(path: a['path'].to_s, at: (a['at'] || 'worktree').to_s)
          end

          tool 'file_context', description: 'Line‑centric file context (before/after) at worktree or HEAD',
                               schema: {
                                 type: 'object',
                                 properties: {
                                   path: { type: 'string' },
                                   line: { type: 'integer', minimum: 1 },
                                   before: { type: 'integer', minimum: 0, maximum: 200 },
                                   after: { type: 'integer', minimum: 0, maximum: 200 },
                                   at: { type: 'string', enum: %w[worktree HEAD] }
                                 },
                                 required: ['path']
                               } do |_ctx, a|
            (engine || Savant::Git::Engine.new).file_context(path: a['path'].to_s, line: a['line'], before: a['before'] || 3, after: a['after'] || 3, at: (a['at'] || 'worktree').to_s)
          end
        end
      end
    end
  end
end
