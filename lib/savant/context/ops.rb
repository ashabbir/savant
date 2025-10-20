#!/usr/bin/env ruby
#
# Purpose: Implements the business logic for Context tools.
#
# Context::Ops hosts the concrete implementations behind the Context MCP tools.
# It contains two functional areas:
# 1) Postgres FTS search across indexed code/content (`#search`, via Context::FTS)
# 2) Filesystem-backed memory_bank helpers (`#search_memory`, `#resources_list`, `#resources_read`).
#
# Design:
# - Keep this layer deterministic and stateless; no global config reads.
# - Memory bank operations default to the current working directory, or accept
#   an explicit repo root path. They do not consult app config to resolve repos.
# - Heavy I/O or DB work is delegated to helper classes to keep Ops small.
#
require 'json'
require_relative '../logger'

module Savant
  module Context
    class Ops
      # Create an Ops instance with a namespaced logger.
      def initialize
        @log = Savant::Logger.new(component: 'context.ops')
      end

      # Query Postgres FTS for code/content chunks.
      # Params:
      # - q: String query
      # - repo: Optional String repository name to scope results
      # - limit: Integer max results
      # Returns: Array of Hashes with rel_path, chunk, lang, score
      def search(q:, repo:, limit:)
        require_relative 'fts'
        Savant::Context::FTS.new.search(q: q, repo: repo, limit: limit)
      end

      # Search memory_bank markdown on the filesystem beneath a repo root.
      # - q: String query (required)
      # - repo: Optional filesystem path to repo root (defaults to Dir.pwd)
      # - limit: Integer max results
      # Returns: { results: [ { path, title, score, snippets, metadata } ], total }
      def search_memory(q:, repo:, limit:)
        require_relative 'memory_bank/indexer'
        root = (repo && File.directory?(repo)) ? File.expand_path(repo) : Dir.pwd
        repo_name = File.basename(root)
        mbi = Savant::Context::MemoryBank::Indexer.new(repo_name: repo_name, repo_root: root, config: {})
        idx = mbi.scan
        window = Integer(ENV['MEMORY_BANK_SNIPPET_WINDOW'] || 160) rescue 160
        windows = Integer(ENV['MEMORY_BANK_WINDOWS_PER_DOC'] || 2) rescue 2
        mbi.search(idx, q, max_results: limit, snippet_window: window, windows_per_doc: windows)
      end

      # List available memory_bank resources under a repo root (or CWD).
      # Returns: Array of { uri, mimeType, metadata: { path, title, size_bytes, modified_at, source } }
      def resources_list(repo: nil)
        require_relative 'memory_bank/indexer'
        root = (repo && File.directory?(repo)) ? File.expand_path(repo) : Dir.pwd
        repo_name = File.basename(root)
        mbi = Savant::Context::MemoryBank::Indexer.new(repo_name: repo_name, repo_root: root, config: {})
        idx = mbi.scan
        idx.resources.map do |r|
          { uri: r.uri, mimeType: r.mime_type, metadata: { path: r.path, title: r.title, size_bytes: r.size_bytes, modified_at: r.modified_at, source: r.source } }
        end
      end

      # Read a memory_bank resource by a repo:// URI.
      # The method resolves the file by searching for a matching path beneath
      # the current working directory (and SAVANT_PATH if provided).
      # Raises: 'unsupported uri' if non-memory_bank; 'resource not found' otherwise.
      def resources_read(uri:)
        unless uri.start_with?('repo://') && uri.include?('/memory-bank/')
          raise 'unsupported uri'
        end
        rel = uri.split('/memory-bank/', 2)[1]
        # Try to resolve the file relative to current project tree
        candidates = []
        candidates << File.join(Dir.pwd, 'memory_bank', rel)
        candidates += Dir.glob(File.join(Dir.pwd, '**', 'memory_bank', rel))
        if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
          base = File.expand_path(ENV['SAVANT_PATH'])
          candidates << File.join(base, 'memory_bank', rel)
          candidates += Dir.glob(File.join(base, '**', 'memory_bank', rel))
        end
        path = candidates.find { |p| File.file?(p) }
        raise 'resource not found' unless path
        File.read(path)
      end
    end
  end
end
