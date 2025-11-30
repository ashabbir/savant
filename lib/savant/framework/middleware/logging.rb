# frozen_string_literal: true

module Savant
  module Framework
    module Middleware
      # Logging middleware that wraps tool calls with start/end events
      # and logs exceptions in structured JSON.
      class Logging
      def initialize(app, logger:)
        @app = app
        @logger = logger
      end

      def call(ctx, tool_name, payload)
        start = now_ms
        @logger.trace(event: 'tool_start', service: ctx[:service], tool: tool_name, request_id: ctx[:request_id])
        result = @app.call(ctx, tool_name, payload)
        dur = now_ms - start
        @logger.trace(event: 'tool_end', service: ctx[:service], tool: tool_name, request_id: ctx[:request_id],
                      duration_ms: dur, status: 'ok')
        result
      rescue StandardError => e
        dur = now_ms - start
        @logger.error(event: 'exception', service: ctx[:service], tool: tool_name, request_id: ctx[:request_id],
                      message: e.message, duration_ms: dur)
        raise
      end

      private

      def now_ms
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
      end
      end
    end
  end
end
