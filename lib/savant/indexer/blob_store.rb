#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Persistence layer for repos, files, blobs, and chunks.
#
# Provides CRUD helpers over Savant::DB for the indexing pipeline, including
# ensuring repos, upserting files, creating blobs, writing/replacing chunks,
# mapping files to blobs, and cleaning up missing files.

module Savant
  module Indexer
    # Persistence adapter wrapping {Savant::DB} for indexer writes.
    #
    # Purpose: Provide a narrow, intention-revealing API for the indexing
    # pipeline to store repos, files, blobs, mappings, and chunks.
    class BlobStore
      def initialize(db)
        @db = db
      end

      def ensure_repo(name, root)
        @db.find_or_create_repo(name, root)
      end

      def ensure_blob(hash, size)
        @db.find_or_create_blob(hash, size)
      end

      def write_chunks(blob_id, chunks)
        @db.replace_chunks(blob_id, chunks)
      end

      def upsert_file(repo_id, repo_name, rel_path, size, mtime_ns)
        @db.upsert_file(repo_id, repo_name, rel_path, size, mtime_ns)
      end

      def map_file(file_id, blob_id)
        @db.map_file_to_blob(file_id, blob_id)
      end

      def cleanup_missing(repo_id, kept_rel_paths)
        @db.delete_missing_files(repo_id, kept_rel_paths)
      end

      # Execute the given block within a DB transaction when available.
      # @yield [] block executed transactionally
      # @return [Object] yield result
      def with_transaction(&)
        if @db.respond_to?(:with_transaction)
          @db.with_transaction(&)
        else
          yield
        end
      end
    end
  end
end
