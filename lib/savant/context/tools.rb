require 'json'
require_relative 'engine'

module Savant
  module Context
    module Tools
      module_function

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
            description: 'Search memory_bank markdown resources',
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
          { name: 'resources/list', description: 'List memory_bank resources', inputSchema: { type: 'object', properties: { repo: { type: 'string' } } } },
          { name: 'resources/read', description: 'Read a memory_bank resource by URI', inputSchema: { type: 'object', properties: { uri: { type: 'string' } }, required: ['uri'] } }
        ]
      end

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

