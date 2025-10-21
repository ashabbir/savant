#!/usr/bin/env ruby

require_relative 'tool'
require_relative 'registrar'

module Savant
  module MCP
    module Core
      module DSL
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

          def registrar
            @registrar
          end
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

