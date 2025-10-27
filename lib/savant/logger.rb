#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'time'

#
# Purpose: Minimal, fast logger with levels and timing.
#
# Provides component-scoped log output with level filtering via `LOG_LEVEL` and
# a simple `with_timing` helper that marks slow operations using
# `SLOW_THRESHOLD_MS`. Defaults to stdout but accepts any IO for writing.

module Savant
  # Structured logger with levels, JSON formatting, and timing.
  class Logger
    LEVELS = %w[trace debug info warn error].freeze

    # Options: io:, level:, json:, service:, tool:
    def initialize(io: $stdout, level: :info, json: true, service: nil, tool: nil)
      @io = io
      @json = json
      @level = level.to_s
      @service = service
      @tool = tool
      @slow_threshold_ms = (ENV['SLOW_THRESHOLD_MS'] || '2000').to_i
    end

    def level_enabled?(lvl)
      LEVELS.index(lvl) >= LEVELS.index(@level)
    end

    %w[trace debug info warn error].each do |lvl|
      define_method(lvl) do |payload = {}|
        return unless level_enabled?(lvl)
        log(lvl, payload)
      end
    end

    def with_timing(label: nil)
      start = current_time_ms
      result = yield
      dur = current_time_ms - start
      slow = dur > @slow_threshold_ms
      trace(event: label || 'timing', duration_ms: dur, slow: slow)
      [result, dur]
    end

    private

    def log(level, payload)
      base = {
        timestamp: Time.now.utc.iso8601,
        level: level,
        service: @service,
        tool: @tool
      }
      data = base.merge(symbolize_keys(payload))
      if @json
        @io.puts(JSON.generate(data))
      else
        @io.puts(format_text(data))
      end
    end

    def symbolize_keys(h)
      return {} unless h
      h.each_with_object({}) { |(k, v), acc| acc[(k.is_a?(String) ? k.to_sym : k)] = v }
    end

    def format_text(data)
      msg = data[:message] || data[:event]
      "#{data[:timestamp]} #{data[:level]} #{data[:service]} #{data[:tool]} #{msg}"
    end

    def current_time_ms
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
    end
  end
end
