#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Facade for the indexing pipeline.
#
# Wires configuration, cache, and runner to perform end-to-end repository
# scans and persistence to Postgres. This is the stable entry used by CLI
# and scripts; detailed logic is implemented in submodules under indexer/.

require 'json'
require 'digest'
require_relative 'framework/config'
require_relative 'framework/db'
require_relative 'logging/logger'

module Savant
  module Indexer
    # Facade class for running the indexer end-to-end.
    #
    # Purpose: Stable entrypoint wiring config, cache and runner. Used by
    # CLI to index or reindex repos without exposing internals.
    class Facade
      def initialize(settings_path, logger: Savant::Logging::Logger.new(io: $stdout, json: true, service: 'indexer'), db: Savant::Framework::DB.new)
        @settings_path = settings_path
        @logger = logger
        @db = db
      end

      def run(repo_name = nil, verbose: true)
        cfg = Savant::Indexer::Config.new(Savant::Framework::Config.load(@settings_path))
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
