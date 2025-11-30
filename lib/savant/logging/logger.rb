#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'time'
require 'fileutils'

#
# Purpose: Minimal, fast logger with levels and timing.
#
# Provides component-scoped log output with level filtering via `LOG_LEVEL` and
# a simple `with_timing` helper that marks slow operations using
# `SLOW_THRESHOLD_MS`. Defaults to stdout but accepts any IO for writing.

module Savant
  module Logging
    # Structured logger with levels, JSON formatting, and timing.
    class Logger
    LEVELS = %w[trace debug info warn error].freeze

    # Options: io:, file_path:, level:, json:, service:, tool:
    # rubocop:disable Metrics/ParameterLists
    def initialize(io: $stdout, file_path: nil, level: :error, json: true, service: nil, tool: nil)
      @io = io
      @file_path = file_path
      @json = json
      @level = level.to_s
      @service = service
      @tool = tool
      @slow_threshold_ms = (ENV['SLOW_THRESHOLD_MS'] || '2000').to_i
      @file_io = init_file_io(file_path)
    end
    # rubocop:enable Metrics/ParameterLists

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
      line = if @json
               JSON.generate(data)
             else
               format_text(data)
             end
      if @io
        @io.puts(line)
        @io.flush if @io.respond_to?(:flush)
      end
      return unless @file_io

      @file_io.puts(line)
      @file_io.flush
    end

    def symbolize_keys(payload)
      return {} if payload.nil?

      if payload.is_a?(Hash)
        payload.transform_keys { |k| (k.is_a?(String) ? k.to_sym : k) }
      else
        { message: payload.to_s }
      end
    end

    def format_text(data)
      msg = data[:message] || data[:event]
      "#{data[:timestamp]} #{data[:level]} #{data[:service]} #{data[:tool]} #{msg}"
    end

    def current_time_ms
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
    end

    def init_file_io(path)
      return nil unless path && !path.to_s.empty?

      dir = File.dirname(path)
      FileUtils.mkdir_p(dir)
      File.open(path, 'a')
    rescue StandardError
      nil
    end
  end
  end
end
