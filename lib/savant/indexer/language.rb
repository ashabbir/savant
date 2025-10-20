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

