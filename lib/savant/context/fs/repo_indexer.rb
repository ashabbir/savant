#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Expose repository indexing under the Context::FS namespace.

require_relative '../../indexer'
require_relative '../../db'
require_relative '../../logger'

module Savant
  module Context
    module FS
      # Wrapper exposing indexer operations within the Context namespace.
      #
      # Purpose: Allow Context tools to trigger index, delete, and status
      # operations without importing the indexer CLI.
      class RepoIndexer
        def initialize(db: Savant::DB.new, settings_path: 'config/settings.json',
                       logger: Savant::Logger.new(component: 'context.repo_indexer'))
          @settings_path = settings_path
          @logger = logger
          @db = db
        end

        def index(repo: nil, verbose: true)
          idx = Savant::Indexer::Facade.new(@settings_path, logger: @logger, db: @db)
          idx.run(repo, verbose: verbose)
        end

        def delete(repo: nil)
          if repo.nil? || repo == 'all'
            @db.delete_all_data
            { deleted: 'all', count: 1 }
          else
            n = @db.delete_repo_by_name(repo)
            { deleted: 'repo', count: n }
          end
        end

        def status
          admin = Savant::Indexer::Admin.new(@db)
          rows = admin.repo_stats
          rows.map do |r|
            max_ns = r['max_mtime_ns']
            last_ts = max_ns ? Time.at(max_ns.to_i / 1_000_000_000.0).utc.iso8601 : nil
            {
              'name' => r['name'],
              'files' => r['files'].to_i,
              'blobs' => r['blobs'].to_i,
              'chunks' => r['chunks'].to_i,
              'last_mtime' => last_ts
            }
          end
        end
      end
    end
  end
end
