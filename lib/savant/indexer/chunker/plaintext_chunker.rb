#!/usr/bin/env ruby
#
# Purpose: Chunk plaintext using the code chunking strategy.
#
# Delegates to CodeChunker to keep behavior consistent for unknown/plain files.

module Savant
  module Indexer
    module Chunker
      # Plaintext chunker delegating to code chunking semantics.
      #
      # Purpose: Reuse line-based logic for unknown/plain files.
      class PlaintextChunker < Base
        def chunk(path, config)
          # Treat as code-like line chunking for simplicity
          CodeChunker.new.chunk(path, config)
        end
      end
    end
  end
end
