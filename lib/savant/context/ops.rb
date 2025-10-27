#!/usr/bin/env ruby
# frozen_string_literal: true

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
    # Implements Context domain operations (search, memory bank, resources).
    #
    # Purpose: Contain all business logic for Context tools separate from the
    # engine/registrar wiring. Queries Postgres FTS and the filesystem.
    class Ops
      # Create an Ops instance with a namespaced logger.
      # @param db [Savant::DB] database connection wrapper
      def initialize(db: Savant::DB.new)
        @log = Savant::Logger.new(io: $stdout, json: true, service: 'context.ops')
        @db = db
      end

      # Query Postgres FTS for code/content chunks.
      # Params:
      # - q: String query
      # - repo: Optional String or Array of repository names to scope results
      # - limit: Integer max results
      # Returns: Array of Hashes with rel_path, chunk, lang, score
      # Full-text search via Postgres FTS.
      # @param q [String]
      # @param repo [String, Array<String>, nil]
      # @param limit [Integer]
      # @return [Array<Hash>] results with rel_path, chunk, lang, score
      def search(q:, repo:, limit:)
        require_relative 'fts'
        Savant::Context::FTS.new(@db).search(q: q, repo: repo, limit: limit)
      end

      # Search memory_bank markdown stored in Postgres (via FTS), scoped by repo name(s).
      # - q: String query (required)
      # - repo: Optional String or Array of repo names; when nil searches all repos
      # - limit: Integer max results
      # Returns: Array of Hashes with repo, rel_path, chunk, lang, score
      # Search memory bank content only (markdown) via FTS.
      # @param q [String]
      # @param repo [String, Array<String>, nil]
      # @param limit [Integer]
      # @return [Array<Hash>]
      def search_memory(q:, repo:, limit:)
        require_relative 'fts'
        Savant::Context::FTS.new(@db).search(q: q, repo: repo, limit: limit, memory_only: true)
      end

      # List memory_bank resources from the database (files table) using repo_name and rel_path.
      # Returns: Array of { uri, mimeType, metadata: { path, title, size_bytes, modified_at, source } }
      # List memory bank resources from the database for a repo.
      # @param repo [String, Array<String>, nil]
      # @return [Array<Hash>] { uri, mimeType, metadata }
      def resources_list(repo: nil)
        conn = @db.instance_variable_get(:@conn)
        params = []
        where = "WHERE rel_path LIKE '%/memory_bank/%' AND rel_path ILIKE '%.md'"
        if repo
          if repo.is_a?(Array)
            ph = repo.each_index.map { |i| "$#{i + 1}" }.join(',')
            where << " AND repo_name IN (#{ph})"
            params.concat(repo)
          else
            where << ' AND repo_name = $1'
            params << repo
          end
        end
        sql = <<~SQL
          SELECT repo_name, rel_path, size_bytes, mtime_ns
          FROM files
          #{where}
          ORDER BY repo_name, rel_path
        SQL
        rows = conn.exec_params(sql, params)
        rows.map do |r|
          repo_name = r['repo_name']
          rel_path = r['rel_path']
          uri = "repo://#{repo_name}/memory-bank/#{rel_path}"
          title = File.basename(rel_path, File.extname(rel_path))
          modified_at = begin
            Time.at(r['mtime_ns'].to_i / 1_000_000_000.0).utc.iso8601
          rescue StandardError
            nil
          end
          { uri: uri, mimeType: 'text/markdown; charset=utf-8',
            metadata: { path: rel_path, title: title, modified_at: modified_at, source: 'memory_bank' } }
        end
      end

      # Read a memory_bank resource by a repo:// URI using DB to resolve repo roots.
      # URI format: repo://<repo_name>/memory-bank/<rel_path>
      # Returns file contents from filesystem rooted at repos.root_path.
      # Read a memory bank resource by repo:// URI.
      # @param uri [String] repo://<repo>/memory-bank/<rel_path>
      # @return [String] raw markdown contents
      def resources_read(uri:)
        raise 'unsupported uri' unless uri.start_with?('repo://') && uri.include?('/memory-bank/')

        head, tail = uri.split('/memory-bank/', 2)
        repo_name = head.sub('repo://', '')
        # Tail could be either full rel_path or just the path under memory_bank; try both
        rel_candidates = []
        rel_candidates << tail
        rel_candidates << File.join('memory_bank', tail) unless tail.include?('/memory_bank/')

        conn = @db.instance_variable_get(:@conn)
        # Resolve repo root
        r = conn.exec_params('SELECT root_path FROM repos WHERE name=$1', [repo_name])
        raise 'resource not found' if r.ntuples.zero?

        root = r[0]['root_path']
        # Find a matching file row to validate existence
        rel = nil
        rel_candidates.each do |cand|
          rr = conn.exec_params('SELECT 1 FROM files WHERE repo_name=$1 AND rel_path=$2', [repo_name, cand])
          if rr.ntuples.positive?
            rel = cand
            break
          end
        end
        # Fallback: try suffix match under memory_bank
        if rel.nil?
          rr = conn.exec_params(
            "SELECT rel_path FROM files WHERE repo_name=$1 AND rel_path LIKE '%/memory_bank/%' AND rel_path LIKE $2 LIMIT 1", [
              repo_name, "%#{tail}"
            ]
          )
          rel = rr[0]['rel_path'] if rr.ntuples.positive?
        end
        raise 'resource not found' unless rel

        path = File.join(root, rel)
        raise 'resource not found' unless File.file?(path)

        File.read(path)
      end

      private

      # Resolve a repo identifier to a filesystem root path.
      # Accepts a direct path or a logical repo name stored in the DB `repos` table.
      # Resolve a repo identifier to a filesystem root path.
      # @param repo [String, nil]
      # @return [String] absolute path
      def resolve_repo_root(repo)
        return Dir.pwd if repo.nil? || repo.to_s.strip.empty?
        return File.expand_path(repo) if File.directory?(repo)

        # Try DB lookup by repo name
        begin
          require_relative '../db'
          db = Savant::DB.new
          res = db.instance_variable_get(:@conn).exec_params('SELECT root_path FROM repos WHERE name=$1', [repo.to_s])
          if res.ntuples.positive?
            root = res[0]['root_path']
            return File.expand_path(root)
          end
        rescue StandardError => _e
          # Fallback to CWD if DB lookup fails
        end
        Dir.pwd
      end
    end
  end
end
