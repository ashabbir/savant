module Savant
  module Indexer
    module Chunker
      class CodeChunker < Base
        def chunk(path, config)
          data = File.read(path)
          max_lines = config.fetch('codeMaxLines')
          overlap = config.fetch('overlapLines')
          lines = data.lines
          slices = []
          i = 0
          while i < lines.length
            j = [i + max_lines, lines.length].min
            slices << lines[i...j].join
            break if j >= lines.length
            next_i = j - overlap
            i = next_i <= i ? j : next_i
          end
          slices
        end
      end
    end
  end
end

