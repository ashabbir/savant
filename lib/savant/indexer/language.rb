#!/usr/bin/env ruby
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
        ext = File.extname(rel).downcase.sub('.', '')
        ext.empty? ? 'txt' : ext
      end
    end
  end
end
