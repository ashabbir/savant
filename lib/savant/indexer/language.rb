#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Infer language from file path/extension for chunking.
#
# Maps file extensions to a coarse language label used by the indexer for
# filtering and chunking strategy selection.

module Savant
  module Indexer
    # Derives a coarse language label from a relative path.
    #
    # Purpose: Choose chunking strategy and optional language allow‑listing.
    class Language
      def self.from_rel_path(rel)
        down = rel.downcase
        # Treat markdown under memory directories as memory_bank (supports multiple variants)
        # Variants: memory, memoryBank, memory_bank, memory-bank, bank
        segments = down.split('/')
        norm_segments = segments.map { |s| s.gsub(/[-_]/, '') }
        if norm_segments.any? { |s| s == 'memory' || s == 'memorybank' || s == 'bank' }
          if %w[.md .mdx .markdown].include?(File.extname(down))
            return 'memory_bank'
          end
        end

        ext = File.extname(down).sub('.', '')
        ext.empty? ? 'txt' : ext
      end
    end
  end
end
