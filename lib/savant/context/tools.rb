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

module Savant
  module Context
    module Tools
      module_function

      # Return an array of MCP tool specifications for the Context service.
      def specs
        [
          # FTS search (code + docs)
          {
            name: 'fts/search',
            description: 'Full‑text search over indexed repos (filter by repo name(s))',
            inputSchema: {
              type: 'object',
              properties: {
                q: { type: 'string' },
                repo: {
                  anyOf: [
                    { type: 'string' },
                    { type: 'array', items: { type: 'string' } },
                    { type: 'null' }
                  ],
                  description: 'Optional repo name or list of repo names'
                },
                limit: { type: 'integer', minimum: 1, maximum: 100 }
              },
              required: ['q']
            }
          },
          # Memory bank FTS search
          {
            name: 'memory/search',
            description: 'Search memory_bank markdown in DB FTS (filter by repo name(s))',
            inputSchema: {
              type: 'object',
              properties: {
                q: { type: 'string' },
                repo: {
                  anyOf: [
                    { type: 'string' },
                    { type: 'array', items: { type: 'string' } },
                    { type: 'null' }
                  ],
                  description: 'Optional repo name or list of names'
                },
                limit: { type: 'integer', minimum: 1, maximum: 100 }
              },
              required: ['q']
            }
          },
          # Memory bank filesystem helpers
          { name: 'memory/resources/list', description: 'List memory_bank resources from DB (optional repo filter)', inputSchema: { type: 'object', properties: { repo: { anyOf: [{ type: 'string' }, { type: 'array', items: { type: 'string' } }, { type: 'null' } ] } } } },
          { name: 'memory/resources/read', description: 'Read a memory_bank resource by URI', inputSchema: { type: 'object', properties: { uri: { type: 'string' } }, required: ['uri'] } },
          # Repo indexer (filesystem → DB)
          {
            name: 'fs/repo/index',
            description: 'Index all repos or a single repo by name',
            inputSchema: {
              type: 'object',
              properties: {
                repo: { anyOf: [{ type: 'string' }, { type: 'null' }], description: 'Repo name or null for all' },
                verbose: { type: 'boolean' }
              }
            }
          },
          {
            name: 'fs/repo/delete',
            description: 'Delete all indexed data or a single repo by name',
            inputSchema: {
              type: 'object',
              properties: {
                repo: { anyOf: [{ type: 'string' }, { type: 'null' }], description: 'Repo name or "all" or null for all' }
              }
            }
          },
          {
            name: 'fs/repo/status',
            description: 'List per-repo index status counts',
            inputSchema: { type: 'object', properties: {} }
          }
        ]
      end

      # Dispatch an MCP tool invocation to the engine.
      # Params:
      # - engine: Context::Engine instance
      # - name: String tool name
      # - args: Hash of input args
      # Returns: Tool result object as a plain Ruby object
      def dispatch(engine, name, args)
        case name
        when 'fts/search'
          limit = begin
            Integer(args['limit'] || 10)
          rescue
            10
          end
          engine.search(q: (args['q'] || '').to_s, repo: args['repo'], limit: limit)
        when 'memory/search'
          limit = begin
            Integer(args['limit'] || 20)
          rescue
            20
          end
          engine.search_memory(q: (args['q'] || '').to_s, repo: args['repo'], limit: limit)
        when 'memory/resources/list'
          engine.resources_list(repo: args['repo'])
        when 'memory/resources/read'
          engine.resources_read(uri: (args['uri'] || '').to_s)
        when 'fs/repo/index'
          engine.repo_indexer_index(repo: args['repo'], verbose: !!args['verbose'])
        when 'fs/repo/delete'
          engine.repo_indexer_delete(repo: args['repo'])
        when 'fs/repo/status'
          engine.repo_indexer_status
        else
          raise 'Unknown Context tool'
        end
      end
    end
  end
end
