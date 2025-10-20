#!/usr/bin/env ruby
#
# Purpose: Postgres connection + schema helpers.
#
# Provides a small wrapper around the pg connection used across Savant. It
# includes helpers to create/migrate core tables, ensure the FTS GIN index, and
# run transactional blocks. CRUD for indexing lives in BlobStore; this class is
# intentionally focused on connection lifecycle and schema operations.

require 'pg'

module Savant
  class DB
    def initialize(url = ENV['DATABASE_URL'])
      @url = url
      @conn = PG.connect(@url)
    end

    def with_transaction
      @conn.exec('BEGIN')
      begin
        yield
        @conn.exec('COMMIT')
      rescue => e
        @conn.exec('ROLLBACK') rescue nil
        raise e
      end
    end

    def close
      @conn.close if @conn
    end

    def migrate_tables
      # Destructive reset: drop and recreate all tables/indexes
      @conn.exec('DROP TABLE IF EXISTS file_blob_map CASCADE')
      @conn.exec('DROP TABLE IF EXISTS chunks CASCADE')
      @conn.exec('DROP TABLE IF EXISTS files CASCADE')
      @conn.exec('DROP TABLE IF EXISTS blobs CASCADE')
      @conn.exec('DROP TABLE IF EXISTS repos CASCADE')

      @conn.exec(<<~SQL)
        CREATE TABLE repos (
          id SERIAL PRIMARY KEY,
          name TEXT UNIQUE NOT NULL,
          root_path TEXT NOT NULL
        );
      SQL

      @conn.exec(<<~SQL)
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
      @conn.exec("CREATE INDEX idx_files_repo_name ON files(repo_name)")
      @conn.exec("CREATE INDEX idx_files_repo_id ON files(repo_id)")

      @conn.exec(<<~SQL)
        CREATE TABLE blobs (
          id SERIAL PRIMARY KEY,
          hash TEXT UNIQUE NOT NULL,
          byte_len BIGINT NOT NULL
        );
      SQL

      @conn.exec(<<~SQL)
        CREATE TABLE file_blob_map (
          file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
          blob_id INTEGER NOT NULL REFERENCES blobs(id) ON DELETE CASCADE,
          PRIMARY KEY(file_id)
        );
      SQL

      @conn.exec(<<~SQL)
        CREATE TABLE chunks (
          id SERIAL PRIMARY KEY,
          blob_id INTEGER NOT NULL REFERENCES blobs(id) ON DELETE CASCADE,
          idx INTEGER NOT NULL,
          lang TEXT,
          chunk_text TEXT NOT NULL
        );
      SQL
      @conn.exec("CREATE INDEX idx_chunks_blob ON chunks(blob_id)")
      true
    end

    def ensure_fts
      @conn.exec(<<~SQL)
        CREATE INDEX IF NOT EXISTS idx_chunks_fts ON chunks USING GIN (to_tsvector('english', chunk_text));
      SQL
      true
    end

    def find_or_create_blob(hash, byte_len)
      res = @conn.exec_params('SELECT id FROM blobs WHERE hash=$1', [hash])
      return res[0]['id'].to_i if res.ntuples > 0
      res = @conn.exec_params('INSERT INTO blobs(hash, byte_len) VALUES($1,$2) RETURNING id', [hash, byte_len])
      res[0]['id'].to_i
    end

    def replace_chunks(blob_id, chunks)
      @conn.exec_params('DELETE FROM chunks WHERE blob_id=$1', [blob_id])
      chunks.each do |idx, lang, text|
        @conn.exec_params('INSERT INTO chunks(blob_id, idx, lang, chunk_text) VALUES($1,$2,$3,$4)', [blob_id, idx, lang, text])
      end
      true
    end

    def find_or_create_repo(name, root)
      res = @conn.exec_params('SELECT id FROM repos WHERE name=$1', [name])
      return res[0]['id'].to_i if res.ntuples > 0
      res = @conn.exec_params('INSERT INTO repos(name, root_path) VALUES($1,$2) RETURNING id', [name, root])
      res[0]['id'].to_i
    end

    def upsert_file(repo_id, repo_name, rel_path, size_bytes, mtime_ns)
      res = @conn.exec_params(
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

    def map_file_to_blob(file_id, blob_id)
      @conn.exec_params(
        <<~SQL, [file_id, blob_id]
          INSERT INTO file_blob_map(file_id, blob_id)
          VALUES($1,$2)
          ON CONFLICT (file_id) DO UPDATE SET blob_id=EXCLUDED.blob_id
        SQL
      )
      true
    end

    def delete_missing_files(repo_id, keep_rels)
      if keep_rels.empty?
        @conn.exec_params('DELETE FROM files WHERE repo_id=$1', [repo_id])
      else
        # Use a dynamic parameter list to avoid malformed array literals
        placeholders = keep_rels.each_index.map { |i| "$#{i + 2}" }.join(',')
        sql = "DELETE FROM files WHERE repo_id=$1 AND rel_path NOT IN (#{placeholders})"
        @conn.exec_params(sql, [repo_id] + keep_rels)
      end
      true
    end

    def delete_repo_by_name(name)
      res = @conn.exec_params('SELECT id FROM repos WHERE name=$1', [name])
      return 0 if res.ntuples.zero?
      rid = res[0]['id']
      @conn.exec_params('DELETE FROM repos WHERE id=$1', [rid])
      1
    end

    def delete_all_data
      @conn.exec('DELETE FROM file_blob_map')
      @conn.exec('DELETE FROM files')
      @conn.exec('DELETE FROM chunks')
      @conn.exec('DELETE FROM blobs')
      @conn.exec('DELETE FROM repos')
      true
    end
  end
end
