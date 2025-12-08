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
        info("repo=#{name} files=#{total} strategy=#{strategy}")
      end

      # rubocop:disable Metrics/AbcSize
      def repo_stats(name:, total:, indexed:, skipped:, errors:, skip_reasons:, type_counts:,
                     code_breakdown:, doc_breakdown:, memory_bank:)
        # Summary line: repo=name files=N (type1=N type2=N ...)
        types_str = type_counts.sort_by { |_, v| -v }.map { |k, v| "#{k}=#{v}" }.join(' ')
        info("  files: #{total} (#{types_str})")

        # Breakdown by category
        if code_breakdown.any?
          code_str = code_breakdown.sort_by { |_, v| -v }.map { |k, v| "#{k}=#{v}" }.join(' ')
          info("  code: #{code_breakdown.values.sum} (#{code_str})")
        end
        if doc_breakdown.any?
          doc_str = doc_breakdown.sort_by { |_, v| -v }.map { |k, v| "#{k}=#{v}" }.join(' ')
          info("  docs: #{doc_breakdown.values.sum} (#{doc_str})")
        end
        info("  memory_bank: #{memory_bank}") if memory_bank.positive?

        # Indexing results
        info("  indexed: #{indexed} skipped: #{skipped} errors: #{errors}")

        # Skip reasons breakdown
        if skip_reasons.any?
          reasons_str = skip_reasons.sort_by { |_, v| -v }.map { |k, v| "#{k}=#{v}" }.join(' ')
          info("  skip_reasons: #{reasons_str}")
        end
        info('')
      end
      # rubocop:enable Metrics/AbcSize

      def repo_footer(indexed:, skipped:, errors: 0)
        # Legacy footer - kept for compatibility but stats now handled by repo_stats
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
      # Quiet mode (default) suppresses progress output since detailed stats shown at end.
      class TextProgress
        def initialize(_logger, title:, total:, quiet: true)
          @title = title
          @total = total
          @current = 0
          @quiet = quiet
        end

        def increment
          @current += 1
        end

        def finish
          @current = @total
        end
      end
    end
  end
end
