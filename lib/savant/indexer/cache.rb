require 'json'

#!/usr/bin/env ruby
#
# Purpose: Simple JSON-backed cache for indexing metadata.
#
# Stores per-file metadata (size, mtime) to skip unchanged files between runs.
# Provides hash-like access and persists to disk on save.

module Savant
  module Indexer
    # JSON-backed cache for file metadata between runs.
    #
    # Purpose: Record file size and mtime to quickly detect unchanged files
    # and skip expensive hashing/chunking.
    class Cache
      def initialize(path)
        @path = path
        @data = load
      end

      def [](k)
        @data[k]
      end

      def []=(k, v)
        @data[k] = v
      end

      # Persist the cache to disk.
      # @return [void]
      def save!
        dir = File.dirname(@path)
        Dir.mkdir(dir) unless Dir.exist?(dir)
        File.write(@path, JSON.pretty_generate(@data))
      end

      private

      def load
        File.exist?(@path) ? JSON.parse(File.read(@path)) : {}
      end
    end
  end
end
