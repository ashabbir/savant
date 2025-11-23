#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Postgres FTS helper for Context search.
#
# Context::FTS encapsulates the SQL used to perform full‑text search over
# chunked content stored in Postgres. It returns ranked results of chunks,
# optionally scoped to a specific repository name. This class holds the minimal
# DB coupling needed by Context::Ops and favors explicit SQL for transparency.
#
require_relative '../db'

module Savant
  module Context
    # Thin Postgres FTS helper used by Context::Ops.
    #
    # Purpose: Run ranked full‑text queries and return tuples suitable for
    # tool responses without leaking SQL to callers.
    class FTS
      # Initialize with a DB connection wrapper. Accepts a Savant::DB or any
      # object exposing `@conn` compatible with pg's exec_params.
      # @param db [Savant::DB]
      def initialize(db)
        @db = db
      end

      # Run a search against the FTS index.
      # Params:
      # - q: String query
      # - repo: Optional String or Array of repository names to scope results
      # - limit: Integer max results
      # - memory_only: Boolean; if true restrict to memory_bank paths
      # Returns: Array of Hashes with repo, rel_path, chunk, lang, score (Float)
      # Ranked full-text search over `chunks` with optional repo scope.
      # @param q [String]
      # @param repo [String, Array<String>, nil]
      # @param limit [Integer]
      # @param memory_only [Boolean] restrict to memory_bank markdown
      # @return [Array<Hash>] rows with rel_path, chunk, lang, score
      def search(q:, repo: nil, limit: 10, memory_only: false)
        repo_list = case repo
                    when nil then nil
                    when String then [repo]
                    when Array then repo
                    else Array(repo)
                    end

        where_repo = ''
        where_mb = ''
        params = [q]

        if repo_list && !repo_list.empty?
          # Build an IN clause with parameter placeholders to avoid casting issues
          placeholders = repo_list.each_index.map { |i| "$#{i + 2}" }.join(',')
          where_repo = " AND f.repo_name IN (#{placeholders})"
          params.concat(repo_list)
        end

        memory_patterns = []
        if memory_only
          # Include common directory variants for memory bank
          memory_patterns = [
            '%/memory/%', '%/memory_bank/%', '%/memory-bank/%', '%/memorybank/%', '%/memoryBank/%', '%/bank/%'
          ]
          rlen = repo_list&.length || 0
          # Build OR chain for ILIKE patterns
          placeholders = memory_patterns.each_index.map { |i| "$#{2 + rlen + i}" }
          where_mb = " AND (" + placeholders.map { |ph| "f.rel_path ILIKE #{ph}" }.join(' OR ') + ")"
        end

        # Append memory patterns and limit
        params.concat(memory_patterns)
        # Limit is always last param
        params << limit

        sql = <<~SQL
          SELECT f.repo_name AS repo, f.rel_path, c.chunk_text AS chunk, c.lang,
            ts_rank(to_tsvector('english', c.chunk_text), plainto_tsquery('english', $1)) AS score
          FROM chunks c
          JOIN blobs b ON b.id = c.blob_id
          JOIN file_blob_map fb ON fb.blob_id = b.id
          JOIN files f ON f.id = fb.file_id
          WHERE to_tsvector('english', c.chunk_text) @@ plainto_tsquery('english', $1)
          #{where_repo}
          #{where_mb}
          ORDER BY score DESC
          LIMIT $#{1 + (repo_list&.length || 0) + (memory_only ? memory_patterns.length : 0) + 1}
        SQL

        res = @db.with_connection { |conn| conn.exec_params(sql, params) }
        res.map do |row|
          {
            'repo' => row['repo'],
            'rel_path' => row['rel_path'],
            'chunk' => row['chunk'],
            'lang' => row['lang'],
            'score' => row['score'].to_f
          }
        end
      end
    end
  end
end
