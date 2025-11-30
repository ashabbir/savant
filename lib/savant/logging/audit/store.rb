# frozen_string_literal: true

require 'json'
require 'fileutils'

module Savant
  module Logging
    module Audit
      # Simple append-only JSONL audit log writer used by the trace middleware.
      class Store
      def initialize(path)
        @path = path
        ensure_dir
      end

      def append(entry)
        return unless @path && !@path.empty?

        File.open(@path, 'a') do |fh|
          fh.puts(JSON.generate(entry))
        end
      end

      private

      def ensure_dir
        return unless @path

        dir = File.dirname(@path)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      end
    end
    end
  end
end
