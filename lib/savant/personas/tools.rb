#!/usr/bin/env ruby
# Tools registrar for Savant::Personas

require_relative '../mcp/core/dsl'

module Savant
  module Personas
    module Tools
      module_function

      def build_registrar(engine)
        Savant::MCP::Core::DSL.build do
          tool 'personas/hello', description: 'Example hello tool',
               schema: { type: 'object', properties: { name: { type: 'string' } } } do |_ctx, a|
            { hello: (a['name'] || 'world') }
          end
        end
      end
    end
  end
end
