#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Postgres connection + schema helpers.
#
# Provides a small wrapper around the pg connection used across Savant. It
# includes helpers to create/migrate core tables, ensure the FTS GIN index, and
# run transactional blocks. CRUD for indexing lives in BlobStore; this class is
# intentionally focused on connection lifecycle and schema operations.

require 'pg'

module Savant
  module Framework
    # Connection + schema helper around Postgres.
    #
    # Purpose: Centralize DB lifecycle and schema/CRUD helpers used by the
    # indexer and context engines. Keeps business logic out of SQL access.
    #
    # Typical usage creates an instance per process and reuses a single
    # connection; callers may use transaction helpers for multi-step writes.
    # rubocop:disable Metrics/ClassLength
    class DB
    # @param url [String] Postgres connection URL (uses `ENV['DATABASE_URL']`).
    def initialize(url = ENV.fetch('DATABASE_URL', nil))
      @url = url
      @mutex = Mutex.new
      @conn = PG.connect(@url)
      configure_client_min_messages
    end

    def connection
      ensure_connection!
      @conn
    end

    def with_connection
      @mutex.synchronize do
        ensure_connection!
        yield @conn
      end
    rescue PG::UnableToSend, PG::ConnectionBad
      @mutex.synchronize do
        reconnect!
        yield @conn
      end
    end

    def exec(sql)
      with_connection { |conn| conn.exec(sql) }
    end

    def exec_params(sql, params)
      with_connection { |conn| conn.exec_params(sql, params) }
    end

    def reconnect!
      begin
        @conn&.close
      rescue StandardError
        nil
      end
      @conn = PG.connect(@url)
      configure_client_min_messages
    end

    def ensure_connection!
      reconnect! if @conn.nil? || @conn.finished? || @conn.status != PG::CONNECTION_OK
    rescue PG::Error
      reconnect!
    end

    # Execute a block inside a DB transaction.
    # @yield Runs inside BEGIN/COMMIT; ROLLBACK on errors.
    # @return [Object] yields return value.
    def with_transaction
      exec('BEGIN')
      begin
        yield
        exec('COMMIT')
      rescue StandardError => e
        begin
          exec('ROLLBACK')
        rescue StandardError
          nil
        end
        raise e
      end
    end

    def close
      @conn&.close
      @conn = nil
    end

    # Drop and recreate all schema tables and indexes.
    # @return [true]
    def migrate_tables
      # Destructive reset: drop and recreate all tables/indexes
      exec('DROP TABLE IF EXISTS file_blob_map CASCADE')
      exec('DROP TABLE IF EXISTS chunks CASCADE')
      exec('DROP TABLE IF EXISTS files CASCADE')
      exec('DROP TABLE IF EXISTS blobs CASCADE')
      exec('DROP TABLE IF EXISTS repos CASCADE')

      exec(<<~SQL)
        CREATE TABLE repos (
          id SERIAL PRIMARY KEY,
          name TEXT UNIQUE NOT NULL,
          root_path TEXT NOT NULL
        );
      SQL

      exec(<<~SQL)
        CREATE TABLE files (
          id SERIAL PRIMARY KEY,
          repo_id INTEGER NOT NULL REFERENCES repos(id) ON DELETE CASCADE,
          repo_name TEXT NOT NULL,
          rel_path TEXT NOT NULL,
          size_bytes BIGINT NOT NULL,
          mtime_ns BIGINT NOT NULL,
          UNIQUE(repo_id, rel_path)
        );
      SQL
      exec('CREATE INDEX idx_files_repo_name ON files(repo_name)')
      exec('CREATE INDEX idx_files_repo_id ON files(repo_id)')

      exec(<<~SQL)
        CREATE TABLE blobs (
          id SERIAL PRIMARY KEY,
          hash TEXT UNIQUE NOT NULL,
          byte_len BIGINT NOT NULL
        );
      SQL

      exec(<<~SQL)
        CREATE TABLE file_blob_map (
          file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
          blob_id INTEGER NOT NULL REFERENCES blobs(id) ON DELETE CASCADE,
          PRIMARY KEY(file_id)
        );
      SQL

      exec(<<~SQL)
        CREATE TABLE chunks (
          id SERIAL PRIMARY KEY,
          blob_id INTEGER NOT NULL REFERENCES blobs(id) ON DELETE CASCADE,
          idx INTEGER NOT NULL,
          lang TEXT,
          chunk_text TEXT NOT NULL
        );
      SQL
      exec('CREATE INDEX idx_chunks_blob ON chunks(blob_id)')
      true
    end

    # Ensure the GIN FTS index on `chunks.chunk_text` exists.
    # @return [true]
    def ensure_fts
      exec(<<~SQL)
        CREATE INDEX IF NOT EXISTS idx_chunks_fts ON chunks USING GIN (to_tsvector('english', chunk_text));
      SQL
      true
    end

    # Fetch an existing blob id by hash or insert a new blob.
    # @param hash [String]
    # @param byte_len [Integer]
    # @return [Integer] blob id
    def find_or_create_blob(hash, byte_len)
      res = exec_params('SELECT id FROM blobs WHERE hash=$1', [hash])
      return res[0]['id'].to_i if res.ntuples.positive?

      res = exec_params('INSERT INTO blobs(hash, byte_len) VALUES($1,$2) RETURNING id', [hash, byte_len])
      res[0]['id'].to_i
    end

    # Replace all chunks for a blob id.
    # @param blob_id [Integer]
    # @param chunks [Array<Array(Integer,String,String)>>] [idx, lang, text]
    # @return [true]
    def replace_chunks(blob_id, chunks)
      exec_params('DELETE FROM chunks WHERE blob_id=$1', [blob_id])
      chunks.each do |idx, lang, text|
        exec_params('INSERT INTO chunks(blob_id, idx, lang, chunk_text) VALUES($1,$2,$3,$4)',
                    [blob_id, idx, lang, text])
      end
      true
    end

    # Fetch an existing repo id by name or insert it with path.
    # @return [Integer] repo id
    def find_or_create_repo(name, root)
      res = exec_params('SELECT id FROM repos WHERE name=$1', [name])
      return res[0]['id'].to_i if res.ntuples.positive?

      res = exec_params('INSERT INTO repos(name, root_path) VALUES($1,$2) RETURNING id', [name, root])
      res[0]['id'].to_i
    end

    # Insert or update a file row and return its id.
    # @return [Integer] file id
    def upsert_file(repo_id, repo_name, rel_path, size_bytes, mtime_ns)
      res = exec_params(
        <<~SQL, [repo_id, repo_name, rel_path, size_bytes, mtime_ns]
          INSERT INTO files(repo_id, repo_name, rel_path, size_bytes, mtime_ns)
          VALUES($1,$2,$3,$4,$5)
          ON CONFLICT (repo_id, rel_path)
          DO UPDATE SET repo_name=EXCLUDED.repo_name, size_bytes=EXCLUDED.size_bytes, mtime_ns=EXCLUDED.mtime_ns
          RETURNING id
        SQL
      )
      res[0]['id'].to_i
    end

    # Map a file id to a blob id (upsert).
    # @return [true]
    def map_file_to_blob(file_id, blob_id)
      exec_params(
        <<~SQL, [file_id, blob_id]
          INSERT INTO file_blob_map(file_id, blob_id)
          VALUES($1,$2)
          ON CONFLICT (file_id) DO UPDATE SET blob_id=EXCLUDED.blob_id
        SQL
      )
      true
    end

    # Delete files for a repo not present in `keep_rels`.
    # @param repo_id [Integer]
    # @param keep_rels [Array<String>]
    # @return [true]
    def delete_missing_files(repo_id, keep_rels)
      if keep_rels.empty?
        exec_params('DELETE FROM files WHERE repo_id=$1', [repo_id])
      else
        # Use a single array parameter to avoid very large parameter lists
        sql = 'DELETE FROM files WHERE repo_id=$1 AND NOT (rel_path = ANY($2::text[]))'
        exec_params(sql, [repo_id, text_array_encoder.encode(keep_rels)])
      end
      true
    end

    # Delete a repository and all its data by name.
    # @return [Integer] number of repos deleted (0/1)
    def delete_repo_by_name(name)
      res = exec_params('SELECT id FROM repos WHERE name=$1', [name])
      return 0 if res.ntuples.zero?

      rid = res[0]['id']
      exec_params('DELETE FROM repos WHERE id=$1', [rid])
      1
    end

    # Truncate all data from all tables (destructive).
    # @return [true]
    def delete_all_data
      exec('DELETE FROM file_blob_map')
      exec('DELETE FROM files')
      exec('DELETE FROM chunks')
      exec('DELETE FROM blobs')
      exec('DELETE FROM repos')
      true
    end

    # List repos along with the first README chunk stored in the DB.
    # @param filter [String, nil] optional substring filter on repo name
    # @return [Array<Hash>] { name:, readme_text: }
    def list_repos_with_readme(filter: nil)
      params = []
      where_clause = ''
      unless filter.to_s.strip.empty?
        params << "%#{filter}%"
        where_clause = "WHERE r.name ILIKE $#{params.length}"
      end

      sql = <<~SQL
        SELECT r.name, readme.chunk_text AS readme_text
        FROM repos r
        LEFT JOIN LATERAL (
          SELECT c.chunk_text
          FROM files f
          JOIN file_blob_map fb ON fb.file_id = f.id
          JOIN chunks c ON c.blob_id = fb.blob_id
          WHERE f.repo_id = r.id
            AND LOWER(f.rel_path) LIKE 'readme%'
          ORDER BY f.rel_path ASC, c.idx ASC
          LIMIT 1
        ) readme ON true
        #{where_clause}
        ORDER BY r.name ASC
      SQL

      res = exec_params(sql, params)
      res.map { |row| { name: row['name'], readme_text: row['readme_text'] } }
    end

    private

    def text_array_encoder
      @text_array_encoder ||= PG::TextEncoder::Array.new(
        name: 'text[]',
        elements_type: PG::TextEncoder::String.new(name: 'text')
      )
    end

    # Suppress Postgres NOTICE messages (e.g., long word warnings) unless running in debug/trace mode.
    # Controlled by LOG_LEVEL environment variable.
    def configure_client_min_messages
      lvl = (ENV['LOG_LEVEL'] || 'info').to_s.downcase
      min = %w[trace debug].include?(lvl) ? 'NOTICE' : 'WARNING'
      exec("SET client_min_messages TO #{min}")
    rescue StandardError
      # best-effort; ignore if not supported or connection not ready
      nil
    end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
