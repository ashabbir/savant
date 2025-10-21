#!/usr/bin/env ruby
#
# Purpose: Chunk markdown files by fixed character windows.
#
# Produces evenly sized slices (no overlap) controlled by `mdMaxChars`,
# suitable for FTS and snippet extraction.

module Savant
  module Indexer
    module Chunker
      # Splits markdown into fixed-size character windows.
      #
      # Purpose: Produce compact, readable chunks for text search/snippets.
      class MarkdownChunker < Base
        def chunk(path, config)
          data = File.read(path)
          max = config.fetch('mdMaxChars')
          slices = []
          i = 0
          while i < data.length
            j = [i + max, data.length].min
            slices << data[i...j]
            i = j
          end
          slices
        end
      end
    end
  end
end
