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
          {
            name: 'search',
            description: 'Full‑text search over indexed repos',
            inputSchema: {
              type: 'object',
              properties: {
                q: { type: 'string' },
                repo: { anyOf: [{ type: 'string' }, { type: 'null' }] },
                limit: { type: 'integer', minimum: 1, maximum: 100 }
              },
              required: ['q']
            }
          },
          {
            name: 'search_memory',
            description: 'Search memory_bank markdown under a repo path (defaults to CWD)',
            inputSchema: {
              type: 'object',
              properties: {
                q: { type: 'string' },
                repo: { anyOf: [{ type: 'string' }, { type: 'null' }], description: 'Optional path to repo root' },
                limit: { type: 'integer', minimum: 1, maximum: 100 }
              },
              required: ['q']
            }
          },
          { name: 'resources/list', description: 'List memory_bank resources under a repo path (defaults to CWD)', inputSchema: { type: 'object', properties: { repo: { type: 'string' } } } },
          { name: 'resources/read', description: 'Read a memory_bank resource by URI', inputSchema: { type: 'object', properties: { uri: { type: 'string' } }, required: ['uri'] } }
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
        when 'search'
          engine.search(q: (args['q'] || '').to_s, repo: args['repo'], limit: Integer(args['limit'] || 10) rescue 10)
        when 'search_memory'
          engine.search_memory(q: (args['q'] || '').to_s, repo: args['repo'], limit: Integer(args['limit'] || 20) rescue 20)
        when 'resources/list'
          engine.resources_list(repo: args['repo'])
        when 'resources/read'
          engine.resources_read(uri: (args['uri'] || '').to_s)
        else
          raise 'Unknown Context tool'
        end
      end
    end
  end
end
