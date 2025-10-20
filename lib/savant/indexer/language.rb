#!/usr/bin/env ruby
#
# Purpose: Infer language from file path/extension for chunking.
#
# Maps file extensions to a coarse language label used by the indexer for
# filtering and chunking strategy selection.

module Savant
  module Indexer
    class Language
      def self.from_rel_path(rel)
        ext = File.extname(rel).downcase.sub('.', '')
        ext.empty? ? 'txt' : ext
      end
    end
  end
end
