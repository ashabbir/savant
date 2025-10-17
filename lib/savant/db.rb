require 'pg'

module Savant
  class DB
    def initialize(url = ENV['DATABASE_URL'])
      @url = url
      @conn = PG.connect(@url)
    end

    def close
      @conn.close if @conn
    end

    def migrate_tables
      @conn.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS repos (
          id SERIAL PRIMARY KEY,
          name TEXT UNIQUE NOT NULL,
          root_path TEXT NOT NULL
        );
      SQL

      @conn.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS files (
          id SERIAL PRIMARY KEY,
          repo_id INTEGER NOT NULL REFERENCES repos(id) ON DELETE CASCADE,
          rel_path TEXT NOT NULL,
          size_bytes BIGINT NOT NULL,
          mtime_ns BIGINT NOT NULL,
          UNIQUE(repo_id, rel_path)
        );
      SQL

      @conn.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS blobs (
          id SERIAL PRIMARY KEY,
          hash TEXT UNIQUE NOT NULL,
          byte_len BIGINT NOT NULL
        );
      SQL

      @conn.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS file_blob_map (
          file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
          blob_id INTEGER NOT NULL REFERENCES blobs(id) ON DELETE CASCADE,
          PRIMARY KEY(file_id)
        );
      SQL

      @conn.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS chunks (
          id SERIAL PRIMARY KEY,
          blob_id INTEGER NOT NULL REFERENCES blobs(id) ON DELETE CASCADE,
          idx INTEGER NOT NULL,
          lang TEXT,
          chunk_text TEXT NOT NULL
        );
      SQL
      @conn.exec(<<~SQL)
        CREATE INDEX IF NOT EXISTS idx_chunks_blob ON chunks(blob_id);
      SQL
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
  end
end
