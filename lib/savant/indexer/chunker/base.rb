module Savant
  module Indexer
    module Chunker
      class Base
        def chunk(_path, _config)
          raise NotImplementedError
        end
      end
    end
  end
end

