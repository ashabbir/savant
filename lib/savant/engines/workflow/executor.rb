#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'time'
require 'fileutils'

require_relative '../../logging/event_recorder'
require_relative 'context'
require_relative 'interpolator'
require_relative 'agents'

module Savant
  module Workflow
    # Linear workflow executor (deterministic, no branches)
    class Executor
      def initialize(base_path: nil, logger: nil)
        @base_path = base_path || default_base_path
        @logger = logger || default_logger
        @rec = Savant::Logging::EventRecorder.global
        FileUtils.mkdir_p(File.join(@base_path, 'logs'))
        @trace_path = File.join(@base_path, 'logs', 'workflow_trace.log')
        @trace_io = File.open(@trace_path, 'a')
        @trace_io.sync = true
      end

      # spec: { id:, steps: [ { name:, type:, ref:, with: } ] }
      # Returns [final_result, trace]
      def run(spec:, params:, run_id:)
        ctx = Context.new(params: params)
        interp = Interpolator.new(ctx)
        steps_trace = []
        started_at = Time.now.utc.iso8601
        status = 'ok'
        error_msg = nil

        spec[:steps].each_with_index do |step, idx|
          ts0 = current_ms
          with_resolved = interp.apply(step[:with])
          emit_event('workflow_step_started', step: step[:name], type: step[:type].to_s, run_id: run_id, input_summary: summarize(with_resolved))
          begin
            out = case step[:type]
                  when :tool
                    call_tool(step[:ref], with_resolved)
                  when :agent
                    call_agent(step[:ref], with_resolved)
                  else
                    raise "unknown step type: #{step[:type]}"
                  end
            ctx.set(step[:name], out)
            dur = current_ms - ts0
            emit_event('workflow_step_completed', step: step[:name], type: step[:type].to_s, run_id: run_id, duration_ms: dur, output_summary: summarize(out))
            steps_trace << { name: step[:name], type: step[:type].to_s, input: with_resolved, output: truncate(out), duration_ms: dur }
          rescue StandardError => e
            dur = current_ms - ts0
            emit_event('workflow_step_error', step: step[:name], type: step[:type].to_s, run_id: run_id, duration_ms: dur, error: e.message)
            steps_trace << { name: step[:name], type: step[:type].to_s, input: with_resolved, error: e.message, duration_ms: dur }
            status = 'error'
            error_msg = e.message
            break
          end
        end

        final_value = spec[:steps].empty? ? nil : ctx.get(spec[:steps].last[:name])
        trace = { workflow: spec[:id], run_id: run_id, started_at: started_at, finished_at: Time.now.utc.iso8601, status: status, error: error_msg, steps: steps_trace }
        [final_value, trace]
      ensure
        @trace_io&.close
      end

      private

      def normalize_tool_name(ref)
        # Normalize older names (dots/slashes) to the current underscore form
        s = ref.to_s
        return s unless s.include?('.')
        service, name = s.split('.', 2)
        name = name.gsub(/[.\/]/, '_')
        [service, name].join('.')
      end

      def call_tool(ref, args)
        mux = Savant::Framework::Runtime.current&.multiplexer
        raise 'multiplexer_unavailable' unless mux
        tool = normalize_tool_name(ref)
        mux.call(tool, args || {})
      end

      def call_agent(name, with)
        Savant::Workflow::Agents.run(name, with || {})
      end

      def summarize(obj)
        case obj
        when String
          { _summary: 'string', bytes: obj.bytesize, preview: obj.byteslice(0, 200) }
        when Array
          { _summary: 'array', length: obj.length }
        when Hash
          { _summary: 'object', keys: obj.keys.take(20), key_count: obj.keys.length }
        else
          { _summary: obj.class.name }
        end
      end

      def truncate(obj)
        json = JSON.generate(obj) rescue nil
        return obj unless json && json.bytesize > 100_000
        { _truncated: true, _summary: summarize(obj) }
      end

      def emit_event(type, payload)
        ev = { type: 'workflow_step', event: type, timestamp: Time.now.utc.iso8601 }.merge(payload || {})
        @rec.record(ev)
        begin
          @trace_io.puts(JSON.generate(ev))
        rescue StandardError
          # ignore file write errors
        end
        @logger&.info(ev)
      end

      def current_ms
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
      end

      def default_base_path
        if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
          ENV['SAVANT_PATH']
        else
          File.expand_path('../../../../..', __dir__)
        end
      end

      def default_logger
        require_relative '../../logging/logger'
        Savant::Logging::Logger.new(io: $stdout, file_path: File.join(@base_path, 'logs', 'workflow_engine.log'), json: true, service: 'workflow')
      end
    end
  end
end
