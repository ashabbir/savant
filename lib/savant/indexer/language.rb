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
      MEMORY_DIR_NAMES = %w[memory memorybank bank].freeze
      MARKDOWN_EXTS = %w[.md .mdx .markdown].freeze

      def self.from_rel_path(rel)
        down = rel.downcase
        # Treat markdown under memory directories as memory_bank (supports multiple variants)
        # Variants: memory, memoryBank, memory_bank, memory-bank, bank
        segments = down.split('/')
        norm_segments = segments.map { |s| s.gsub(/[-_]/, '') }
        if norm_segments.any? { |s| MEMORY_DIR_NAMES.include?(s) }
          if MARKDOWN_EXTS.include?(File.extname(down))
            return 'memory_bank'
          end
        end

        ext = File.extname(down).sub('.', '')
        ext.empty? ? 'txt' : ext
      end

      # Check if a file is in a memory directory but is NOT a markdown file.
      # These files should be skipped during indexing.
      # @param rel [String] relative path
      # @return [Boolean] true if in memory dir but not markdown
      def self.in_memory_dir_but_not_markdown?(rel)
        down = rel.downcase
        segments = down.split('/')
        norm_segments = segments.map { |s| s.gsub(/[-_]/, '') }
        in_memory_dir = norm_segments.any? { |s| MEMORY_DIR_NAMES.include?(s) }
        return false unless in_memory_dir

        !MARKDOWN_EXTS.include?(File.extname(down))
      end
    end
  end
end
