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
      true
    end
  end
end
