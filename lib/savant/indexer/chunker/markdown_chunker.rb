module Savant
  module Indexer
    module Chunker
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

