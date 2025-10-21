#!/usr/bin/env ruby
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
    module Tools
      module_function

      # Return an array of MCP tool specifications for the Context service.
      def specs
        build_registrar.specs
      end

      # Dispatch an MCP tool invocation to the engine.
      # Params:
      # - engine: Context::Engine instance
      # - name: String tool name
      # - args: Hash of input args
      # Returns: Tool result object as a plain Ruby object
      def dispatch(engine, name, args)
        reg = build_registrar(engine)
        reg.call(name, args || {}, ctx: { engine: engine })
      end

      def build_registrar(engine = nil)
        Savant::MCP::Core::DSL.build do
          # Simple middleware placeholder (timing/logging hooks can be added)
          middleware do |ctx, nm, a, nxt|
            nxt.call(ctx, nm, a)
          end

          tool 'fts/search', description: 'Full‑text search over indexed repos (filter by repo name(s))',
               schema: { type: 'object', properties: { q: { type: 'string' }, repo: { anyOf: [{ type: 'string' }, { type: 'array', items: { type: 'string' } }, { type: 'null' }] }, limit: { type: 'integer', minimum: 1, maximum: 100 } }, required: ['q'] } do |_ctx, a|
            limit = Integer(a['limit'] || 10) rescue 10
            engine.search(q: (a['q'] || '').to_s, repo: a['repo'], limit: limit)
          end

          tool 'memory/search', description: 'Search memory_bank markdown in DB FTS (filter by repo name(s))',
               schema: { type: 'object', properties: { q: { type: 'string' }, repo: { anyOf: [{ type: 'string' }, { type: 'array', items: { type: 'string' } }, { type: 'null' }] }, limit: { type: 'integer', minimum: 1, maximum: 100 } }, required: ['q'] } do |_ctx, a|
            limit = Integer(a['limit'] || 20) rescue 20
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
