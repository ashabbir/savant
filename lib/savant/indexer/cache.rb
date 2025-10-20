require 'json'

module Savant
  module Indexer
    class Cache
      def initialize(path)
        @path = path
        @data = load
      end

      def [](k)
        @data[k]
      end

      def []=(k, v)
        @data[k] = v
      end

      def save!
        dir = File.dirname(@path)
        Dir.mkdir(dir) unless Dir.exist?(dir)
        File.write(@path, JSON.pretty_generate(@data))
      end

      private

      def load
        File.exist?(@path) ? JSON.parse(File.read(@path)) : {}
      end
    end
  end
end

