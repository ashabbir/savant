require 'json'
require_relative '../logger'
require_relative 'ops'

module Savant
  module Context
    class Engine
      def initialize
        @log = Savant::Logger.new(component: 'context.engine')
        @ops = Savant::Context::Ops.new
      end

      def search(q:, repo: nil, limit: 10)
        @ops.search(q: q, repo: repo, limit: limit)
      end

      def search_memory(q:, repo: nil, limit: 20)
        @ops.search_memory(q: q, repo: repo, limit: limit)
      end

      def resources_list(repo: nil)
        @ops.resources_list(repo: repo)
      end

      def resources_read(uri:)
        @ops.resources_read(uri: uri)
      end
    end
  end
end

