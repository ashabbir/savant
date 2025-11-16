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

          def middleware(&)
            @registrar.use_middleware(&)
          end

          def tool(name, description: '', schema: nil, output_schema: nil, &handler)
            raise 'handler block required' unless handler

            schema ||= { type: 'object', properties: {} }
            t = Tool.new(name: name, description: description, schema: schema, output_schema: output_schema, handler: handler)
            @registrar.add_tool(t)
          end

          attr_reader :registrar

          # Load and evaluate all Ruby files under a directory, in sorted order,
          # within the builder context so they can call `tool` and `middleware`.
          def load_dir(path)
            files = Dir.glob(File.join(path.to_s, '**', '*.rb')).sort
            files.each do |f|
              code = File.read(f)
              instance_eval(code, f)
            end
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
