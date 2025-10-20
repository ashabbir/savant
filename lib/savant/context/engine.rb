#!/usr/bin/env ruby
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

module Savant
  module Context
    class Engine
      # Initialize the engine with a namespaced logger and context ops.
      def initialize
        @log = Savant::Logger.new(component: 'context.engine')
        @ops = Savant::Context::Ops.new
      end

      # Full‑text search over indexed content stored in Postgres FTS.
      # Params:
      # - q: String search query (required)
      # - repo: Optional repository name to scope results
      # - limit: Integer max results (default 10)
      # Returns: Array of Hashes: { 'rel_path', 'chunk', 'lang', 'score' }
      def search(q:, repo: nil, limit: 10)
        @ops.search(q: q, repo: repo, limit: limit)
      end

      # Lightweight filesystem search for memory_bank markdown resources.
      # Mirrors Context semantics but avoids DB; see Ops#search_memory.
      def search_memory(q:, repo: nil, limit: 20)
        @ops.search_memory(q: q, repo: repo, limit: limit)
      end

      # List memory_bank resources discoverable from the given repo path or CWD.
      def resources_list(repo: nil)
        @ops.resources_list(repo: repo)
      end

      # Read the contents of a memory_bank resource by its repo:// URI.
      def resources_read(uri:)
        @ops.resources_read(uri: uri)
      end
    end
  end
end
