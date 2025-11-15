# frozen_string_literal: true

require 'json'
require 'fileutils'

# !/usr/bin/env ruby
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
        FileUtils.mkdir_p(dir)
        File.write(@path, JSON.pretty_generate(@data))
      end

      # Remove all cached entries and delete the cache file on disk.
      def reset!
        @data.clear
        delete_file
      end

      # Remove entries for a specific repo and persist if anything changed.
      def remove_repo!(repo_name)
        return if repo_name.nil? || repo_name.to_s.empty?

        prefix = "#{repo_name}::"
        before = @data.length
        @data.delete_if { |k, _| k.start_with?(prefix) }
        save! if before != @data.length
      end

      private

      def delete_file
        FileUtils.rm_f(@path)
      end

      def load
        File.exist?(@path) ? JSON.parse(File.read(@path)) : {}
      end
    end
  end
end
