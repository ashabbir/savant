#!/usr/bin/env ruby
#
# Purpose: Base class for content chunkers used by the indexer.
#
# Defines the `#chunk(path, config)` interface implemented by concrete
# chunkers for code, markdown, and plaintext.

module Savant
  module Indexer
    module Chunker
      # Abstract base class for chunkers.
      #
      # Purpose: Define the shared interface for concrete chunkers.
      class Base
        def chunk(_path, _config)
          raise NotImplementedError
        end
      end
    end
  end
end
