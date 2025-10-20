#!/usr/bin/env ruby
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
    class FTS
      # Initialize with a DB connection wrapper. Accepts a Savant::DB or any
      # object exposing `@conn` compatible with pg's exec_params.
      def initialize(db = Savant::DB.new)
        @db = db
      end

      # Run a search against the FTS index.
      # Params:
      # - q: String query
      # - repo: Optional String repository name to scope results
      # - limit: Integer max results
      # Returns: Array of Hashes with rel_path, chunk, lang, score (Float)
      def search(q:, repo: nil, limit: 10)
        sql = <<~SQL
          SELECT f.rel_path, c.chunk_text AS chunk, c.lang,
            ts_rank(to_tsvector('english', c.chunk_text), plainto_tsquery('english', $1)) AS score
          FROM chunks c
          JOIN blobs b ON b.id = c.blob_id
          JOIN file_blob_map fb ON fb.blob_id = b.id
          JOIN files f ON f.id = fb.file_id
          #{repo ? 'JOIN repos r ON r.id = f.repo_id' : ''}
          WHERE to_tsvector('english', c.chunk_text) @@ plainto_tsquery('english', $1)
          #{repo ? 'AND r.name = $2' : ''}
          ORDER BY score DESC
          LIMIT $#{repo ? 3 : 2}
        SQL
        params = [q]
        params << repo if repo
        params << limit
        res = @db.instance_variable_get(:@conn).exec_params(sql, params)
        res.map { |row| { 'rel_path' => row['rel_path'], 'chunk' => row['chunk'], 'lang' => row['lang'], 'score' => row['score'].to_f } }
      end
    end
  end
end
