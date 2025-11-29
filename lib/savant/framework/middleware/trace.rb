# frozen_string_literal: true

require 'securerandom'
require 'time'

require_relative '../../logging/logger'
require_relative '../../logging/audit/policy'
require_relative '../../logging/audit/store'
require_relative '../../logging/metrics'
require_relative '../../logging/replay_buffer'
require_relative 'metrics'

module Savant
  module Framework
    module Middleware
      # Wraps tool executions with trace IDs, audit logging, and metrics emission.
      class Trace
      attr_reader :replay_buffer

      def initialize(logger_factory: nil, metrics: Savant::Framework::Middleware::Metrics.new,
                     audit_store: nil, policy: Savant::Logging::Audit::Policy.new, replay_buffer: nil)
        @logger_factory = logger_factory || default_logger_factory
        @metrics_helper = metrics.is_a?(Savant::Framework::Middleware::Metrics) ? metrics : Savant::Framework::Middleware::Metrics.new(metrics: metrics)
        @policy = policy || Savant::Logging::Audit::Policy.new
        @audit_store = (audit_store || Savant::Logging::Audit::Store.new(@policy.audit_store_path) if @policy.audit_enabled?)
        @replay_buffer = replay_buffer || Savant::Logging::ReplayBuffer.new(limit: @policy.replay_limit)
      end

      def call(ctx, tool, payload)
        raise ArgumentError, 'middleware requires a block' unless block_given?

        ctx ||= {}
        service = ctx[:service] || 'savant'
        @policy.enforce!(tool: tool, requires_system: !ctx[:requires_system].nil?, sandbox_override: !ctx[:sandbox_override].nil?)
        trace_id = (ctx[:trace_id] ||= SecureRandom.uuid)
        logger = logger_for(ctx)

        start_ms = now_ms
        @metrics_helper.record_start(tool: tool, service: service)
        log_event(logger, 'tool_start',
                  tool: tool,
                  trace_id: trace_id,
                  service: service)
        append_audit(tool: tool, service: service, trace_id: trace_id, status: 'start')

        begin
          result = yield(ctx, tool, payload)
          duration_ms = now_ms - start_ms
          @metrics_helper.record_finish(tool: tool, service: service, duration_ms: duration_ms, error: false)
          log_event(logger, 'tool_end',
                    tool: tool,
                    trace_id: trace_id,
                    service: service,
                    duration_ms: duration_ms,
                    status: 'success')
          append_audit(tool: tool, service: service, trace_id: trace_id, status: 'success', duration_ms: duration_ms)
          record_replay(tool: tool, service: service, trace_id: trace_id, status: 'success', duration_ms: duration_ms,
                        payload: payload)
          result
        rescue StandardError => e
          duration_ms = now_ms - start_ms
          @metrics_helper.record_finish(tool: tool, service: service, duration_ms: duration_ms, error: true)
          log_event(logger, 'tool_error',
                    tool: tool,
                    trace_id: trace_id,
                    service: service,
                    duration_ms: duration_ms,
                    status: 'error',
                    error: e.message,
                    error_class: e.class.name)
          append_audit(tool: tool, service: service, trace_id: trace_id, status: 'error',
                       duration_ms: duration_ms, error: e.message)
          record_replay(tool: tool, service: service, trace_id: trace_id, status: 'error',
                        duration_ms: duration_ms, payload: payload, error: e.message)
          raise
        end
      end

      private

      def record_replay(entry)
        return unless @replay_buffer

        @replay_buffer.push(entry.merge(timestamp: Time.now.utc.iso8601))
      end

      def append_audit(entry)
        return unless @audit_store

        @audit_store.append(entry.merge(timestamp: Time.now.utc.iso8601))
      end

      def log_event(logger, event, attrs = {})
        payload = { event: event }.merge(attrs)
        if payload[:status] == 'error'
          logger.error(payload)
        else
          logger.trace(payload)
        end
      end

      def logger_for(ctx)
        @logger_factory.call(ctx)
      end

      def default_logger_factory
        lambda do |ctx|
          ctx[:logger] || Savant::Logging::Logger.new(io: $stdout, json: true, service: ctx[:service] || 'savant')
        end
      end

      def now_ms
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
      end
      end
    end
  end
end
