#!/usr/bin/env ruby
#
# Purpose: Minimal, fast logger with levels and timing.
#
# Provides component-scoped log output with level filtering via `LOG_LEVEL` and
# a simple `with_timing` helper that marks slow operations using
# `SLOW_THRESHOLD_MS`. Defaults to stdout but accepts any IO for writing.

module Savant
  # Minimal component logger with levels and timing.
  #
  # Purpose: Provide a lightweight, dependency-free logger suitable for CLI and
  # MCP servers. Supports level filtering via `LOG_LEVEL` and timing via
  # `with_timing`, marking slow operations using `SLOW_THRESHOLD_MS`.
  class Logger
    LEVELS = %w[debug info warn error].freeze

    # @param component [String] label included in every log line.
    # @param out [IO] output stream (defaults to `$stdout`).
    def initialize(component:, out: $stdout)
      @component = component
      @out = out
      @level = (ENV["LOG_LEVEL"] || "info").downcase
      @slow_threshold_ms = (ENV["SLOW_THRESHOLD_MS"] || "2000").to_i
    end

    def level_enabled?(lvl)
      LEVELS.index(lvl) >= LEVELS.index(@level)
    end

    def debug(msg)
      log('debug', msg) if level_enabled?('debug')
    end

    def info(msg)
      log('info', msg) if level_enabled?('info')
    end

    def warn(msg)
      log('warn', msg) if level_enabled?('warn')
    end

    def error(msg)
      log('error', msg)
    end

    # Measure the duration of a block and log it.
    # @param label [String] prefix label for the timing log.
    # @return [Array(Object,Integer)] pair of [block_result, duration_ms]
    def with_timing(label: nil)
      start = current_time_ms
      result = yield
      dur = current_time_ms - start
      slow = dur > @slow_threshold_ms
      suffix = " dur=#{dur}ms"
      suffix += " slow=true threshold_ms=#{@slow_threshold_ms}" if slow
      info([label, suffix].compact.join(':')) if label
      [result, dur]
    end

    private

    def log(level, msg)
      ts = Time.now.utc.strftime('%H:%M:%SZ')
      @out.puts("[#{@component}] #{level}: #{msg} @#{ts}")
    end

    def current_time_ms
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
    end
  end
end
