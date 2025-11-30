#!/usr/bin/env ruby
# frozen_string_literal: true

module Savant
  module Framework
    module MCP
      module Core
        # Represents a single MCP tool specification and handler.
        #
        # Purpose: Pair JSON schema, name, and callable used by registrars.
        class Tool
          attr_reader :name, :description, :schema, :output_schema, :handler

          def initialize(name:, description:, schema:, handler:, output_schema: nil)
            @name = name
            @description = description
            @schema = schema || { type: 'object', properties: {} }
            @output_schema = output_schema
            @handler = handler
          end

          def spec
            spec = { name: @name, description: @description, inputSchema: @schema }
            spec[:outputSchema] = @output_schema if @output_schema
            spec
          end
        end
      end
    end
  end
end
