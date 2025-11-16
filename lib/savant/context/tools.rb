#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: MCP registrar/dispatcher for Context tools.
#
# Context::Tools declares the MCP tools exposed by the Context service and
# dispatches tool calls to an Engine instance. It provides the tool specs
# (name, description, JSON schema) used by the MCP server to advertise
# capabilities and validate inputs.
#
require 'json'
require_relative 'engine'
require_relative '../mcp/core/dsl'

module Savant
  module Context
    # MCP tools registrar for the Context service.
    #
    # Purpose: Advertise tool specs and dispatch invocations to Engine.
    module Tools
      module_function

      # Return the MCP tool specs for the Context service.
      # @return [Array<Hash>] tool definitions
      def specs
        build_registrar.specs
      end

      # Dispatch a tool call by name to the Context engine.
      # @param engine [Savant::Context::Engine]
      # @param name [String]
      # @param args [Hash]
      # @return [Object] tool-specific result
      def dispatch(engine, name, args)
        reg = build_registrar(engine)
        base_ctx = { engine: engine, service: 'context' }
        base_ctx[:logger] = engine&.logger
        reg.call(name, args || {}, ctx: base_ctx)
      end

      # Build the registrar containing all Context tools.
      # @param engine [Savant::Context::Engine, nil]
      # @return [Savant::MCP::Core::Registrar]
      def build_registrar(engine = nil)
        Savant::MCP::Core::DSL.build do
          # Validation middleware using tool schema
          require_relative '../mcp/core/validation'
          middleware do |ctx, nm, a, nxt|
            schema = ctx[:schema]
            begin
              a2 = Savant::MCP::Core::Validation.validate!(schema, a)
            rescue Savant::MCP::Core::ValidationError => e
              raise "validation error: #{e.message}"
            end
            nxt.call(ctx, nm, a2)
          end

          tool 'fts/search', description: 'Full‑text search over indexed repos (filter by repo name(s))',
                             schema: { type: 'object', properties: { q: { type: 'string' }, repo: { anyOf: [{ type: 'string' }, { type: 'array', items: { type: 'string' } }, { type: 'null' }] }, limit: { type: 'integer', minimum: 1, maximum: 100 } }, required: ['q'] } do |_ctx, a|
            limit = begin
              Integer(a['limit'] || 10)
            rescue StandardError
              10
            end
            engine.search(q: (a['q'] || '').to_s, repo: a['repo'], limit: limit)
          end

          tool 'memory/search', description: 'Search memory_bank markdown in DB FTS (filter by repo name(s))',
                                schema: { type: 'object', properties: { q: { type: 'string' }, repo: { anyOf: [{ type: 'string' }, { type: 'array', items: { type: 'string' } }, { type: 'null' }] }, limit: { type: 'integer', minimum: 1, maximum: 100 } }, required: ['q'] } do |_ctx, a|
            limit = begin
              Integer(a['limit'] || 20)
            rescue StandardError
              20
            end
            engine.search_memory(q: (a['q'] || '').to_s, repo: a['repo'], limit: limit)
          end

          tool 'memory/resources/list', description: 'List memory_bank resources from DB (optional repo filter)',
                                        schema: { type: 'object', properties: { repo: { anyOf: [{ type: 'string' }, { type: 'array', items: { type: 'string' } }, { type: 'null' }] } } } do |_ctx, a|
            engine.resources_list(repo: a['repo'])
          end

          tool 'memory/resources/read', description: 'Read a memory_bank resource by URI',
                                        schema: { type: 'object', properties: { uri: { type: 'string' } }, required: ['uri'] } do |_ctx, a|
            engine.resources_read(uri: (a['uri'] || '').to_s)
          end

          tool 'repos/list', description: 'List indexed repos with README excerpts',
                             schema: { type: 'object', properties: { filter: { type: 'string' }, max_length: { type: 'integer', minimum: 256, maximum: 16_384 } } } do |_ctx, a|
            limit = begin
              Integer(a['max_length'] || 4096)
            rescue StandardError
              4096
            end
            engine.repos_readme_list(filter: a['filter'], max_length: limit)
          end

          tool 'fs/repo/index', description: 'Index all repos or a single repo by name',
                                schema: { type: 'object', properties: { repo: { anyOf: [{ type: 'string' }, { type: 'null' }] }, verbose: { type: 'boolean' } } } do |_ctx, a|
            engine.repo_indexer_index(repo: a['repo'], verbose: !!a['verbose'])
          end

          tool 'fs/repo/delete', description: 'Delete all indexed data or a single repo by name',
                                 schema: { type: 'object', properties: { repo: { anyOf: [{ type: 'string' }, { type: 'null' }] } } } do |_ctx, a|
            engine.repo_indexer_delete(repo: a['repo'])
          end

          tool 'fs/repo/status', description: 'List per-repo index status counts',
                                 schema: { type: 'object', properties: {} } do |_ctx, _a|
            engine.repo_indexer_status
          end
        end
      end
    end
  end
end
