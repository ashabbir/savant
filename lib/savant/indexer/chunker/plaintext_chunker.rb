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

