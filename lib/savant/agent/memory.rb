#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'

module Savant
  module Agent
    # Simple memory container with persistent snapshots.
    class Memory
      DEFAULT_PATH = '.savant/session.json'

      attr_reader :data, :path

      def initialize(base_path:, logger: nil)
        @base_path = base_path
        @logger = logger
        @path = File.join(base_path, DEFAULT_PATH)
        @data = {
          steps: [],
          errors: [],
          summaries: [],
          state: {}
        }
        ensure_dir
      end

      def append_step(step)
        @data[:steps] << step
      end

      def append_error(err)
        @data[:errors] << err
      end

      def snapshot!
        # Trim if too large (rough budget ~4k tokens => ~16k chars)
        truncate_if_needed!
        File.write(@path, JSON.pretty_generate(@data))
        @logger&.trace(event: 'agent_memory_snapshot', path: @path, steps: @data[:steps].size, errors: @data[:errors].size)
      rescue StandardError => e
        @logger&.warn(event: 'agent_memory_snapshot_failed', error: e.message)
      end

      private

      def ensure_dir
        dir = File.dirname(@path)
        FileUtils.mkdir_p(dir)
      rescue StandardError
        # ignore
      end

      def truncate_if_needed!
        json = JSON.generate(@data)
        return if json.length <= 16_000

        # Summarize older steps to keep size small
        if @data[:steps].size > 5
          keep = @data[:steps].last(5)
          summarized = { index: 'summary', note: "Summarized #{(@data[:steps].size - 5)} earlier steps" }
          @data[:steps] = [summarized] + keep
        end
      end
    end
  end
end

