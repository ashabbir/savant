require 'json'
require 'digest'
require_relative 'config'
require_relative 'db'
require_relative 'logger'

module Savant
  module Indexer
    # Facade class for running the indexer end-to-end.
    class Facade
      def initialize(settings_path, logger: Savant::Logger.new(component: 'indexer'), db: Savant::DB.new)
        @settings_path = settings_path
        @logger = logger
        @db = db
      end

      def run(repo_name = nil, verbose: true)
        cfg = Savant::Indexer::Config.new(Savant::Config.load(@settings_path))
        cache = Savant::Indexer::Cache.new(cfg.cache_path)
        runner = Savant::Indexer::Runner.new(
          config: cfg,
          db: @db,
          logger: @logger,
          cache: cache
        )
        runner.run(repo_name: repo_name, verbose: verbose)
      end
    end

    # Require submodules
    require_relative 'indexer/config'
    require_relative 'indexer/cache'
    require_relative 'indexer/instrumentation'
    require_relative 'indexer/language'
    require_relative 'indexer/chunker/base'
    require_relative 'indexer/chunker/code_chunker'
    require_relative 'indexer/chunker/markdown_chunker'
    require_relative 'indexer/chunker/plaintext_chunker'
    require_relative 'indexer/repository_scanner'
    require_relative 'indexer/blob_store'
    require_relative 'indexer/runner'
    require_relative 'indexer/admin'
    require_relative 'indexer/cli'
  end
  # Legacy alias to allow external code to call Savant::Index.new(...)
  class Index < Savant::Indexer::Facade; end
end
