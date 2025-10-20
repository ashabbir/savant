#!/usr/bin/env ruby
#
# Purpose: Chunk plaintext using the code chunking strategy.
#
# Delegates to CodeChunker to keep behavior consistent for unknown/plain files.

module Savant
  module Indexer
    module Chunker
      class PlaintextChunker < Base
        def chunk(path, config)
          # Treat as code-like line chunking for simplicity
          CodeChunker.new.chunk(path, config)
        end
      end
    end
  end
end
