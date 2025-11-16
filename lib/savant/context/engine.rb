#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Context engine orchestrator for the Context MCP service.
#
# The Context::Engine is a thin coordinator that wires Context tools to their
# underlying operations. It exposes high-level methods used by the MCP tools
# registrar and delegates all logic to Context::Ops. This class intentionally
# contains no business logic; it provides a stable surface for the MCP server
# and a single place to attach engine-level logging or cross-cutting concerns.
#
# Responsibilities:
# - Construct and hold a Context::Ops instance
# - Provide methods `search`, `search_memory`, `resources_list`, `resources_read`
# - Forward calls to Ops and return results as plain Ruby objects
#
require 'json'
require_relative '../logger'
require_relative 'ops'
require_relative 'fs/repo_indexer'

module Savant
  module Context
    # Orchestrates Context tools and delegates to Ops.
    #
    # Purpose: Provide a stable façade between the MCP server and the Context
    # domain logic (Ops), handling wiring and exposing high-level methods.
    class Engine
      attr_reader :logger

      # Initialize the engine with a namespaced logger and context ops.
      def initialize
        @logger = Savant::Logger.new(io: $stdout, json: true, service: 'context.engine')
        @log = @logger
        @db = Savant::DB.new
        @ops = Savant::Context::Ops.new(db: @db)
      end

      # Full‑text search over indexed content stored in Postgres FTS.
      # Params:
      # - q: String search query (required)
      # - repo: Optional repository name to scope results
      # - limit: Integer max results (default 10)
      # Returns: Array of Hashes: { 'rel_path', 'chunk', 'lang', 'score' }
      # @param q [String] search query
      # @param repo [String, nil] optional repo name scope
      # @param limit [Integer] maximum results to return
      # @return [Array<Hash>] results with rel_path, chunk, lang, score
      def search(q:, repo: nil, limit: 10)
        @ops.search(q: q, repo: repo, limit: limit)
      end

      # Lightweight filesystem search for memory_bank markdown resources.
      # Mirrors Context semantics but avoids DB; see Ops#search_memory.
      # @param q [String] substring to search
      # @param repo [String, nil] optional repo name scope
      # @param limit [Integer] max results
      # @return [Hash] { results:, total: }
      def search_memory(q:, repo: nil, limit: 20)
        @ops.search_memory(q: q, repo: repo, limit: limit)
      end

      # List memory_bank resources discoverable from the given repo path or CWD.
      # @param repo [String, nil] repo name or nil for cwd
      # @return [Array<Hash>] resource entries
      def resources_list(repo: nil)
        @ops.resources_list(repo: repo)
      end

      # Read the contents of a memory_bank resource by its repo:// URI.
      # @param uri [String] repo:// URI of a resource
      # @return [Hash] { uri, mime_type, text }
      def resources_read(uri:)
        @ops.resources_read(uri: uri)
      end

      # Repo Indexer operations exposed under Context
      # @param repo [String, nil] optional repo filter
      # @param verbose [Boolean]
      # @return [Hash] index summary
      def repo_indexer_index(repo: nil, verbose: true)
        Savant::Context::FS::RepoIndexer.new(db: @db).index(repo: repo, verbose: verbose)
      end

      # @param repo [String, nil]
      # @return [Hash] delete summary
      def repo_indexer_delete(repo: nil)
        Savant::Context::FS::RepoIndexer.new(db: @db).delete(repo: repo)
      end

      # @return [Array<Hash>] per-repo status rows
      def repo_indexer_status
        Savant::Context::FS::RepoIndexer.new(db: @db).status
      end

      # List repos and README snippets from indexed data.
      # @param filter [String, nil]
      # @param max_length [Integer]
      # @return [Array<Hash>]
      def repos_readme_list(filter: nil, max_length: 4096)
        @ops.repos_readme_list(filter: filter, max_length: max_length)
      end

      # Server info metadata surfaced to MCP server during initialize
      # Returns: { name:, version:, description: }
      def server_info
        {
          name: 'savant-context',
          version: '1.1.0',
          description: 'Context MCP: fts/search, repos/list, memory/*, fs/repo/*'
        }
      end
    end
  end
end
