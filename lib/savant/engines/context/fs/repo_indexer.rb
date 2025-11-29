#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Expose repository indexing under the Context::FS namespace.

require_relative '../../indexer'
require_relative '../../../framework/db'
require_relative '../../../logging/logger'

module Savant
  module Context
    module FS
      # Wrapper exposing indexer operations within the Context namespace.
      #
      # Purpose: Allow Context tools to trigger index, delete, and status
      # operations without importing the indexer CLI.
      class RepoIndexer
        def initialize(db: Savant::Framework::DB.new, settings_path: 'config/settings.json',
                       logger: Savant::Logging::Logger.new(io: $stdout, json: true, service: 'context.repo_indexer'))
          @settings_path = settings_path
          @logger = logger
          @db = db
        end

        def index(repo: nil, verbose: true)
          idx = Savant::Indexer::Facade.new(@settings_path, logger: @logger, db: @db)
          idx.run(repo, verbose: verbose)
        end

        def delete(repo: nil)
          cache = build_cache
          if repo.nil? || repo == 'all'
            @db.delete_all_data
            cache.reset!
            { deleted: 'all', count: 1 }
          else
            n = @db.delete_repo_by_name(repo)
            cache.remove_repo!(repo)
            { deleted: 'repo', count: n }
          end
        end

        def status
          admin = Savant::Indexer::Admin.new(@db)
          rows = admin.repo_stats
          return [] if rows.nil?

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

        def diagnostics
          info = {}
          base = Dir.pwd
          info[:base_path] = base
          info[:settings_path] = File.expand_path(@settings_path, base)
          repos = []
          cfg_err = nil
          begin
            require_relative '../../framework/config'
            if File.file?(info[:settings_path])
              cfg = Savant::Framework::Config.load(info[:settings_path])
              (cfg.dig('indexer', 'repos') || []).each do |r|
                name = r['name']
                path = r['path']
                entry = { name: name, path: path }
                begin
                  exists = File.exist?(path)
                  entry[:exists] = exists
                  entry[:directory] = exists && File.directory?(path)
                  entry[:readable] = exists && File.readable?(path)
                  if entry[:directory]
                    sample = []
                    count = 0
                    Dir.glob(File.join(path, '**', '*')).each do |p|
                      next if File.directory?(p)

                      sample << p if sample.size < 3
                      count += 1
                      break if count >= 200
                    end
                    entry[:sample_files] = sample
                    entry[:sampled_count] = count
                    entry[:has_files] = count.positive?
                  end
                rescue StandardError => e
                  entry[:error] = e.message
                end
                repos << entry
              end
            else
              cfg_err = 'settings.json not found'
            end
          rescue Savant::ConfigError => e
            cfg_err = e.message
          rescue StandardError => e
            cfg_err = "load error: #{e.message}"
          end
          info[:config_error] = cfg_err if cfg_err
          info[:repos] = repos

          # DB checks
          db = { connected: false }
          begin
            @db.with_connection do |conn|
              db[:status] = conn.status if conn.respond_to?(:status)
              conn.exec('SELECT 1')
              db[:connected] = true
              begin
                r1 = conn.exec('SELECT COUNT(*) AS c FROM repos')
                r2 = conn.exec('SELECT COUNT(*) AS c FROM files')
                r3 = conn.exec('SELECT COUNT(*) AS c FROM chunks')
                db[:counts] = { repos: r1[0]['c'].to_i, files: r2[0]['c'].to_i, chunks: r3[0]['c'].to_i }
              rescue PG::Error => e
                db[:counts_error] = e.message
                db[:connected] = conn.status == PG::CONNECTION_OK if conn.respond_to?(:status)
              rescue StandardError => e
                db[:counts_error] = e.message
              end
            end
          rescue PG::Error => e
            db[:error] = e.message
            db[:connected] = false
          rescue StandardError => e
            db[:error] = e.message
          end
          info[:db] = db

          # Common mount points
          info[:mounts] = {
            '/app' => File.directory?('/app'),
            '/host' => File.directory?('/host'),
            '/host-crawler' => File.directory?('/host-crawler')
          }

          info
        end

        public :diagnostics

        private

        def build_cache
          cfg = Savant::Indexer::Config.new(Savant::Framework::Config.load(@settings_path))
          Savant::Indexer::Cache.new(cfg.cache_path)
        end
      end
    end
  end
end
