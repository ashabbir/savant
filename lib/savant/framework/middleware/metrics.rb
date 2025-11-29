# frozen_string_literal: true

require_relative '../../logging/metrics'

module Savant
  module Middleware
    # Helper object used by Trace middleware to update telemetry metrics.
    class Metrics
      def initialize(metrics: Savant::Logging::Metrics)
        @metrics = metrics
      end

      def record_start(tool:, service:)
        @metrics.increment('tool_invocations_total', tool: tool, service: service)
      end

      def record_finish(tool:, service:, duration_ms:, error: false)
        @metrics.observe('tool_duration_seconds', duration_ms.to_f / 1000.0, tool: tool, service: service)
        @metrics.increment('tool_errors_total', tool: tool, service: service) if error
      end
    end
  end
end
