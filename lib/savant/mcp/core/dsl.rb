#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'tool'
require_relative 'registrar'

module Savant
  module MCP
    module Core
      # Tool definition DSL for building a Registrar with middleware.
      module DSL
        # Builds tool specs via a small internal DSL.
        #
        # Purpose: Make registrar declarations concise and readable.
        class Builder
          def initialize
            @registrar = Registrar.new
          end

          def middleware(&blk)
            @registrar.use_middleware(&blk)
          end

          def tool(name, description: '', schema: nil, &handler)
            raise 'handler block required' unless handler

            schema ||= { type: 'object', properties: {} }
            t = Tool.new(name: name, description: description, schema: schema, handler: handler)
            @registrar.add_tool(t)
          end

          attr_reader :registrar
        end

        module_function

        def build(&blk)
          b = Builder.new
          b.instance_eval(&blk) if blk
          b.registrar
        end
      end
    end
  end
end
