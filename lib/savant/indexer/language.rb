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
        # Treat markdown under memory_bank or memory directories as memory_bank
        if (down.include?('/memory_bank/') || down.include?('/memory/')) &&
           %w[.md .mdx .markdown].include?(File.extname(down))
          return 'memory_bank'
        end

        ext = File.extname(down).sub('.', '')
        ext.empty? ? 'txt' : ext
      end
    end
  end
end
