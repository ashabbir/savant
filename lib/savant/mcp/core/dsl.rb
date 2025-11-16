#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'tool'
require_relative 'registrar'
require_relative '../../logger'
require_relative '../../middleware/trace'
require_relative '../../middleware/metrics'
require_relative '../../audit/policy'
require_relative '../../audit/store'
require_relative '../../telemetry/replay_buffer'

module Savant
  module MCP
    module Core
      # Tool definition DSL for building a Registrar with middleware.
      module DSL
        # Builds tool specs via a small internal DSL.
        #
        # Purpose: Make registrar declarations concise and readable.
        class Builder
          def initialize(policy: nil)
            @registrar = Registrar.new
            @policy = policy || Savant::Audit::Policy.load
            install_framework_middleware
          end

          def middleware(&)
            @registrar.use_middleware(&)
          end

          def install_framework_middleware
            audit_store = @policy.audit_enabled? ? Savant::Audit::Store.new(@policy.audit_store_path) : nil
            metrics = Savant::Middleware::Metrics.new
            trace = Savant::Middleware::Trace.new(logger_factory: method(:logger_for_ctx),
                                                  metrics: metrics,
                                                  audit_store: audit_store,
                                                  policy: @policy)
            @registrar.use_middleware do |ctx, nm, a, nxt|
              trace.call(ctx, nm, a) { nxt.call(ctx, nm, a) }
            end
          end

          def logger_for_ctx(ctx)
            ctx[:logger] || Savant::Logger.new(io: $stdout, json: true, service: ctx[:service] || 'savant')
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
