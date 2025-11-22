#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Thin wrapper over logger for consistent timing and levels.
#
# Allows the indexer to emit structured progress and timing information without
# coupling to a specific logger implementation.

begin
  require 'ruby-progressbar'
rescue LoadError
  nil
end

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

      def with_timing(label:, &)
        if @logger.respond_to?(:with_timing)
          @logger.with_timing(label: label, &)
        else
          start = Time.now
          res = yield
          dur_ms = ((Time.now - start) * 1000).round(1)
          @logger.info("timing: #{label} duration_ms=#{dur_ms}")
          res
        end
      end

      def repo_header(name:, total:, strategy:)
        info("name: #{name}")
        info("total_files: #{total}")
        info("walk_strategy: #{strategy}")
      end

      def repo_footer(indexed:, skipped:, errors: 0)
        info("indexed: #{indexed}")
        info("skipped: #{skipped}")
        info("errors: #{errors}")
        info('====')
      end

      def progress_bar(title:, total:)
        if progress_supported?
          return ProgressBar.create(
            title: title,
            total: total,
            format: '%t %B %p%% %c/%C',
            progress_mark: '#',
            remainder_mark: ' '
          )
        end

        TextProgress.new(@logger, title: title, total: total)
      rescue StandardError
        TextProgress.new(@logger, title: title, total: total)
      end

      private

      def progress_supported?
        defined?(ProgressBar) && tty_output?
      end

      def tty_output?
        $stdout.respond_to?(:tty?) && $stdout.tty?
      rescue IOError
        false
      end

      # Fallback textual progress reporter for non-TTY environments.
      class TextProgress
        CHECKPOINTS = [0, 20, 40, 60, 80, 100].freeze

        def initialize(logger, title:, total:)
          @logger = logger
          @title = title
          @total = total
          @current = 0
          @checkpoints = if @total.to_i <= 0
                           [100]
                         else
                           CHECKPOINTS.dup
                         end
          log_remaining_checkpoints(initial_percentage)
        end

        def increment
          @current += 1
          log_remaining_checkpoints
        end

        def finish
          @current = @total
          log_remaining_checkpoints(percentage)
        end

        private

        def log_remaining_checkpoints(current_pct = percentage)
          while (next_cp = @checkpoints.first) && current_pct >= next_cp
            log(next_cp)
            @checkpoints.shift
          end
        end

        def log(pct)
          bar = build_bar(pct)
          @logger.info("progress: #{@title} #{bar} #{pct}% (#{@current}/#{@total})")
        end

        def percentage
          return 100 if @total.to_i <= 0

          ((@current.to_f / @total) * 100).round
        end

        def initial_percentage
          @total.to_i <= 0 ? 100 : 0
        end

        def build_bar(pct)
          total_ticks = 20
          filled = ((pct / 100.0) * total_ticks).round.clamp(0, total_ticks)
          empty = total_ticks - filled
          "[#{'#' * filled}#{'.' * empty}]"
        end
      end
    end
  end
end
