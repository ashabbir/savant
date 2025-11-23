#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Administrative helpers for indexer/database maintenance.
#
# Provides commands to migrate schema, ensure FTS, perform smoke tests, and
# delete data at repo or global scope.

module Savant
  module Indexer
    # Administrative helpers for DB/indexer maintenance and status.
    #
    # Purpose: Offer reporting (per-repo counts) and schema utilities for
    # CLIs without coupling callers to raw SQL.
    class Admin
      def initialize(db)
        @db = db
      end

      def repo_stats
        @db.with_connection do |conn|
          conn.exec(<<~SQL)
            SELECT r.id, r.name,
                   COUNT(DISTINCT f.id)  AS files,
                   COUNT(DISTINCT b.id)  AS blobs,
                   COUNT(c.id)           AS chunks,
                   MAX(f.mtime_ns)       AS max_mtime_ns
            FROM repos r
            LEFT JOIN files f        ON f.repo_id = r.id
            LEFT JOIN file_blob_map fb ON fb.file_id = f.id
            LEFT JOIN blobs b        ON b.id = fb.blob_id
            LEFT JOIN chunks c       ON c.blob_id = b.id
            GROUP BY r.id, r.name
            ORDER BY r.name;
          SQL
        end
      end

      def self.print_status
        db = Savant::DB.new
        admin = new(db)
        rows = admin.repo_stats
        total_files = 0
        total_blobs = 0
        total_chunks = 0
        puts "STATUS ts=#{Time.now.utc.iso8601} repos=#{rows.ntuples}"
        rows.each do |r|
          max_ns = r['max_mtime_ns']
          last_ts = max_ns ? Time.at(max_ns.to_i / 1_000_000_000.0).utc.iso8601 : '-'
          files  = r['files'].to_i
          blobs  = r['blobs'].to_i
          chunks = r['chunks'].to_i
          total_files  += files
          total_blobs  += blobs
          total_chunks += chunks
          puts "repo=#{r['name']} files=#{files} blobs=#{blobs} chunks=#{chunks} last_mtime=#{last_ts}"
        end
        puts "TOTAL files=#{total_files} blobs=#{total_blobs} chunks=#{total_chunks}"
      end
    end
  end
end
