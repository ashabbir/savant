#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../mcp/core/dsl'
require_relative 'engine'

module Savant
  module Rules
    module Tools
      module_function

      def build_registrar(engine = nil)
        eng = engine || Savant::Rules::Engine.new
        Savant::MCP::Core::DSL.build do
          tool 'rules.list', description: 'List available rule sets',
               schema: { type: 'object', properties: { filter: { type: 'string' } } } do |_ctx, a|
            eng.list(filter: a['filter'])
          end

          tool 'rules.get', description: 'Fetch a ruleset by name',
               schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            eng.get(name: a['name'])
          end
        end
      end
    end
  end
end

