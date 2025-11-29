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
require_relative '../../logging/logger'

module Savant
  module Context
    # Implements Context domain operations (search, memory bank, resources).
    #
    # Purpose: Contain all business logic for Context tools separate from the
    # engine/registrar wiring. Queries Postgres FTS and the filesystem.
    class Ops
      # Create an Ops instance with a namespaced logger.
      # @param db [Savant::DB] database connection wrapper
      def initialize(db: Savant::Framework::DB.new)
        @log = Savant::Logging::Logger.new(io: $stdout, json: true, service: 'context.ops')
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
        params = []
        # Memory dir variants - match both paths starting with memory dir and paths containing it
        mem_patterns = [
          'memory/%', '%/memory/%',
          'memory_bank/%', '%/memory_bank/%',
          'memory-bank/%', '%/memory-bank/%',
          'memorybank/%', '%/memorybank/%',
          'memoryBank/%', '%/memoryBank/%',
          'bank/%', '%/bank/%'
        ]
        # Build memory path clause with positional params
        mem_conditions = mem_patterns.each_index.map { |i| "rel_path ILIKE $#{i + 1}" }.join(' OR ')
        mem_clause = "(#{mem_conditions})"
        params.concat(mem_patterns)
        # Always limit to markdown-like files (md, mdx, markdown)
        clauses = [mem_clause, "(rel_path ILIKE '%.md' OR rel_path ILIKE '%.mdx' OR rel_path ILIKE '%.markdown')"]
        if repo
          if repo.is_a?(Array) && !repo.empty?
            offset = params.length
            ph = (1..repo.length).map { |i| "$#{offset + i}" }.join(',')
            clauses << "repo_name IN (#{ph})"
            params.concat(repo)
          else
            clauses << "repo_name = $#{params.length + 1}"
            params << repo
          end
        end
        where_sql = clauses.empty? ? '' : "WHERE #{clauses.join(' AND ')}"
        sql = <<~SQL
          SELECT repo_name, rel_path, size_bytes, mtime_ns
          FROM files
          #{where_sql}
          ORDER BY repo_name, rel_path
        SQL
        rows = @db.with_connection { |conn| conn.exec_params(sql, params) }
        return [] if rows.nil?

        rows.map do |r|
          repo_name = r['repo_name'] || ''
          rel_path = r['rel_path'] || ''
          next nil if rel_path.empty?

          uri = "repo://#{repo_name}/memory-bank/#{rel_path}"
          title = File.basename(rel_path, File.extname(rel_path))
          modified_at = begin
            Time.at(r['mtime_ns'].to_i / 1_000_000_000.0).utc.iso8601
          rescue StandardError
            nil
          end
          { uri: uri, mimeType: 'text/markdown; charset=utf-8',
            metadata: { path: rel_path, title: title, modified_at: modified_at, source: 'memory_bank' } }
        end.compact
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
        # Try common memory directory variants if the tail isn't already qualified
        unless tail.include?('/memory/') || tail.include?('/memory_bank/') || tail.include?('/memory-bank/') || tail.include?('/memoryBank/') || tail.include?('/memorybank/') || tail.include?('/bank/')
          %w[memory_bank memory memory-bank memoryBank memorybank bank].each do |dir|
            rel_candidates << File.join(dir, tail)
          end
        end

        # Resolve repo root
        r = @db.with_connection { |conn| conn.exec_params('SELECT root_path FROM repos WHERE name=$1', [repo_name]) }
        raise 'resource not found' if r.ntuples.zero?

        root = r[0]['root_path']
        # Find a matching file row to validate existence
        rel = nil
        rel_candidates.each do |cand|
          rr = @db.with_connection do |conn|
            conn.exec_params('SELECT 1 FROM files WHERE repo_name=$1 AND rel_path=$2', [repo_name, cand])
          end
          if rr.ntuples.positive?
            rel = cand
            break
          end
        end
        # Fallback: try suffix match under memory directory variants (case-insensitive)
        if rel.nil?
          patterns = ['%/memory/%', '%/memory_bank/%', '%/memory-bank/%', '%/memorybank/%', '%/memoryBank/%', '%/bank/%']
          # Build OR clause with positional parameters starting at $3
          mem_clause = patterns.each_index.map { |i| "rel_path ILIKE $#{i + 3}" }.join(' OR ')
          sql = "SELECT rel_path FROM files WHERE repo_name=$1 AND (#{mem_clause}) AND rel_path ILIKE $2 LIMIT 1"
          rr = @db.with_connection do |conn|
            conn.exec_params(sql, [repo_name, "%#{tail}"] + patterns)
          end
          rel = rr[0]['rel_path'] if rr.ntuples.positive?
        end
        raise 'resource not found' unless rel

        path = File.join(root, rel)
        raise 'resource not found' unless File.file?(path)

        File.read(path)
      end

      # List repos with their README snippets sourced from indexed data.
      # @param filter [String, nil] optional substring filter on repo name
      # @param max_length [Integer] maximum characters to return per README
      # @return [Array<Hash>] { name:, readme:, truncated: }
      def repos_readme_list(filter: nil, max_length: 4096)
        limit = max_length.to_i
        limit = 4096 if limit <= 0
        rows = @db.list_repos_with_readme(filter: filter)
        rows.map do |row|
          text = row[:readme_text]
          if text.nil?
            { name: row[:name], readme: nil, truncated: false }
          else
            snippet = text[0, limit]
            truncated = text.length > snippet.length
            { name: row[:name], readme: snippet, truncated: truncated }
          end
        end
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
          require_relative '../../framework/db'
          db = Savant::Framework::DB.new
          res = db.with_connection { |conn| conn.exec_params('SELECT root_path FROM repos WHERE name=$1', [repo.to_s]) }
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
