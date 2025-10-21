#!/usr/bin/env ruby

module Savant
  module MCP
    module Core
      class Tool
        attr_reader :name, :description, :schema, :handler

        def initialize(name:, description:, schema:, handler:)
          @name = name
          @description = description
          @schema = schema || { type: 'object', properties: {} }
          @handler = handler
        end

        def spec
          { name: @name, description: @description, inputSchema: @schema }
        end
      end
    end
  end
end

