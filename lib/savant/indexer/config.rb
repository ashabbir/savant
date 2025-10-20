#!/usr/bin/env ruby
#
# Purpose: Strongly-typed view over raw settings for the indexer.
#
# Wraps the parsed settings hash to provide convenient accessors for indexer
# options (max size, languages, chunk config, repos, cache path) and helpers to
# derive scan mode and other behavior.

module Savant
  module Indexer
    class Config
      DEFAULT_CACHE_PATH = '.cache/indexer.json'

      def initialize(raw)
        @raw = raw
      end

      def indexer
        @raw.fetch('indexer')
      end

      def repos
        Array(indexer.fetch('repos'))
      end

      def max_bytes
        indexer.fetch('maxFileSizeKB', 0).to_i * 1024
      end

      def chunk
        indexer.fetch('chunk')
      end

      def languages
        Array(indexer['languages']).map { |s| s.to_s.downcase }
      end

      def cache_path
        indexer['cachePath'] || DEFAULT_CACHE_PATH
      end

      # Global scan mode: auto | git | walk
      def scan_mode
        mode = indexer['scanMode']&.to_s&.downcase
        to_mode_symbol(mode)
      end

      # Per-repo override via repo['scanMode']
      def scan_mode_for(repo_hash)
        rmode = repo_hash['scanMode']&.to_s&.downcase
        to_mode_symbol(rmode) || scan_mode
      end

      private

      def to_mode_symbol(str)
        case str
        when 'git' then :git
        when 'walk' then :walk
        when 'auto' then :auto
        else
          :auto
        end
      end
    end
  end
end
