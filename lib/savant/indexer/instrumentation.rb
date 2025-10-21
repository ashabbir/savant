#!/usr/bin/env ruby
#
# Purpose: Thin wrapper over logger for consistent timing and levels.
#
# Allows the indexer to emit structured progress and timing information without
# coupling to a specific logger implementation.

module Savant
  module Indexer
    # Thin wrapper over logger for consistent timing and levels.
    #
    # Purpose: Decouple indexer code from a concrete logger implementation
    # while offering a uniform API for messages and timing.
    class Instrumentation
      def initialize(logger)
        @logger = logger
      end

      def info(msg)
        @logger.info(msg)
      end

      def debug(msg)
        @logger.debug(msg)
      end

      def with_timing(label:)
        if @logger.respond_to?(:with_timing)
          @logger.with_timing(label: label) { yield }
        else
          start = Time.now
          res = yield
          dur_ms = ((Time.now - start) * 1000).round(1)
          @logger.info("timing: #{label} duration_ms=#{dur_ms}")
          res
        end
      end
    end
  end
end
