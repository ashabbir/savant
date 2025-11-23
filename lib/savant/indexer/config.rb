#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Strongly-typed view over raw settings for the indexer.
#
# Wraps the parsed settings hash to provide convenient accessors for indexer
# options (max size, languages, chunk config, repos, cache path) and helpers to
# derive scan mode and other behavior.

module Savant
  module Indexer
    # Strongly-typed view over raw settings for the indexer.
    #
    # Purpose: Normalize and expose indexer-specific options (repos, size
    # limits, chunking, languages, scan modes) with helpful defaults.
    class Config
      DEFAULT_CACHE_PATH = '.cache/indexer.json'

      def initialize(raw)
        @raw = raw
      end

      def indexer
        @raw.fetch('indexer')
      end

      # @return [Array<Hash>] configured repositories
      def repos
        Array(indexer.fetch('repos'))
      end

      # @return [Integer] maximum file size in bytes (0 = unlimited)
      def max_bytes
        indexer.fetch('maxFileSizeKB', 0).to_i * 1024
      end

      # @return [Hash] chunking configuration
      def chunk
        indexer.fetch('chunk')
      end

      # @return [Array<String>] allowed normalized language codes
      def languages
        Array(indexer['languages']).map { |s| s.to_s.downcase }
      end

      # @return [String] path to indexer cache file
      def cache_path
        indexer['cachePath'] || DEFAULT_CACHE_PATH
      end

      # Global scan mode
      # Allowed values in config: "ls" (default) or "git-ls".
      # Internally we normalize to symbols :walk and :git.
      # @return [:git, :walk]
      def scan_mode
        mode = indexer['scanMode']&.to_s&.downcase
        to_mode_symbol(mode)
      end

      # Per-repo override not supported in this iteration; use global.
      # Present for compatibility with Runner API.
      # @return [:git, :walk]
      def scan_mode_for(_repo_hash)
        # ignore repo_hash and return global
        scan_mode
      end

      private

      def to_mode_symbol(str)
        case str
        when 'git-ls' then :git
        when 'ls' then :walk
        when 'git' then :git # backward compatibility
        when 'walk' then :walk # backward compatibility
        else
          :walk
        end
      end
    end
  end
end
