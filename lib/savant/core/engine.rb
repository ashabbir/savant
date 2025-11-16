#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../logger'

module Savant
  module Core
    # Base engine with lifecycle hook DSL and shared context handle.
    #
    # Usage:
    #   class MyEngine < Savant::Core::Engine
    #     before_call :authenticate
    #     after_call  :audit
    #     # ...
    #   end
    #
    # Hooks receive (ctx, payload) and run around each tool call.
    class Engine
      class << self
        def before_call(method)
          (@before_hooks ||= []) << method.to_sym
        end

        def after_call(method)
          (@after_hooks ||= []) << method.to_sym
        end

        def before_hooks
          @before_hooks || []
        end

        def after_hooks
          @after_hooks || []
        end
      end

      # Engines may optionally be initialized with a shared context instance.
      def initialize(ctx: nil)
        # Lazy require to avoid circular dependency if context requires engine
        begin
          require_relative 'context'
          @ctx = ctx || Savant::Core::Context.new
        rescue LoadError
          @ctx = ctx
        end
      end

      attr_reader :ctx

      # Wrap a tool call, executing registered before/after hooks.
      # The provided block performs the actual tool execution and should
      # return the tool's result.
      def wrap_call(ctx, tool_name, payload)
        run_hooks(self.class.before_hooks, ctx.merge(tool: tool_name), payload)
        out = yield
        run_hooks(self.class.after_hooks, ctx.merge(tool: tool_name), payload)
        out
      end

      private

      def run_hooks(hooks, ctx, payload)
        hooks.each do |m|
          send(m, ctx, payload) if respond_to?(m, true)
        end
      end
    end
  end
end

