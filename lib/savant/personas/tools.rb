#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../mcp/core/dsl'
require_relative 'engine'

module Savant
  module Personas
    # Tools registers personas MCP tool specs.
    module Tools
      module_function

      def build_registrar(engine = nil)
        eng = engine || Savant::Personas::Engine.new
        Savant::MCP::Core::DSL.build do
          # personas.list
          tool 'personas.list', description: 'List available personas',
                                schema: { type: 'object', properties: { filter: { type: 'string' } } } do |_ctx, a|
            eng.list(filter: a['filter'])
          end

          # personas.get
          tool 'personas.get', description: 'Fetch a persona by name',
                               schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            eng.get(name: a['name'])
          end
        end
      end
    end
  end
end
