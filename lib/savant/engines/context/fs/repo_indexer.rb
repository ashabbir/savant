#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Expose repository indexing under the Context::FS namespace.

require_relative '../../indexer'
require_relative '../../../framework/db'
require_relative '../../../framework/config'
require_relative '../../llm/registry'
require_relative '../../../llm/ollama'
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
                       logger: Savant::Logging::MongoLogger.new(service: 'context.repo_indexer'))
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
            require_relative '../../../framework/config'
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
                # Detailed per-table stats for UI table (dynamic list from information_schema)
                begin
                  details = []
                  table_rows = conn.exec(<<~SQL)
                    SELECT table_name
                    FROM information_schema.tables
                    WHERE table_schema = 'public'
                      AND table_type = 'BASE TABLE'
                    ORDER BY table_name
                  SQL
                  table_rows.each do |row|
                    t = row['table_name']
                    begin
                      cols = conn.exec_params("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=$1", [t]).map { |r| r['column_name'] }
                      cnt = conn.exec("SELECT COUNT(*) AS c FROM \"#{t.gsub('"', '""')}\"")[0]['c'].to_i
                      sz = conn.exec_params('SELECT pg_total_relation_size($1::regclass) AS bytes', [t])[0]['bytes'].to_i
                      last_at = nil
                      last_at = conn.exec("SELECT MAX(updated_at) AS m FROM \"#{t.gsub('"', '""')}\"")[0]['m'] if cols.include?('updated_at')
                      if !last_at && cols.include?('created_at')
                        last_at = conn.exec("SELECT MAX(created_at) AS m FROM \"#{t.gsub('"', '""')}\"")[0]['m']
                      end
                      details << { name: t, rows: cnt, size_bytes: sz, last_at: last_at }
                    rescue StandardError => e
                      details << { name: t, error: e.message }
                    end
                  end
                  db[:tables] = details
                rescue StandardError
                  # best effort
                end
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

          # MongoDB checks (optional)
          begin
            mongo = mongo_diagnostics
            info[:mongo] = mongo if mongo
          rescue StandardError => e
            info[:mongo] = { connected: false, error: e.message }
          end

          # Common mount points
          info[:mounts] = {
            '/app' => File.directory?('/app'),
            '/host' => File.directory?('/host'),
            '/host-crawler' => File.directory?('/host-crawler')
          }

          info[:llm_models] = llm_models_info
          info[:llm_runtime] = llm_runtime_info

          info[:secrets] = secrets_info(base)

          # Reasoning API + usage/agents stats
          begin
            info[:reasoning] = reasoning_diagnostics
          rescue StandardError => e
            info[:reasoning] = { configured: false, error: e.message }
          end

          info
        end

        public :diagnostics

        private

        # --- Mongo helpers for diagnostics ---
        def mongo_available?
          return @mongo_available if defined?(@mongo_available)
          begin
            require 'mongo'
            @mongo_available = true
          rescue LoadError
            @mongo_available = false
          end
          @mongo_available
        end

        def mongo_host
          ENV.fetch('MONGO_HOST', 'localhost:27017')
        end

        def mongo_db_name
          env = ENV.fetch('SAVANT_ENV', ENV.fetch('RACK_ENV', ENV.fetch('RAILS_ENV', 'development')))
          env == 'test' ? 'savant_test' : 'savant_development'
        end

        def mongo_client
          return nil unless mongo_available?
          return @mongo_client if defined?(@mongo_client) && @mongo_client

          begin
            uri = ENV.fetch('MONGO_URI', "mongodb://#{mongo_host}/#{mongo_db_name}")
            client = Mongo::Client.new(uri, server_selection_timeout: 1.5, connect_timeout: 1.5, socket_timeout: 2)
            # Ping to ensure connectivity
            client.database.collections
            @mongo_client = client
          rescue StandardError
            @mongo_client = nil
          end
          @mongo_client
        end

        def mongo_diagnostics
          return nil unless mongo_available?

          client = mongo_client
          return { connected: false, db: mongo_db_name } unless client

          out = { connected: true, db: client.database.name }
          begin
            cols = client.database.collections
            out[:counts] = { collections: cols.length, documents: 0 }
            details = []
            cols.each do |col|
              name = col.name.to_s
              begin
                # Fast approximate count
                docs = col.estimated_document_count
                out[:counts][:documents] += docs.to_i
                size_bytes = nil
                last_at = nil
                # Try collStats for size (best effort)
                begin
                  stats = client.database.command(collStats: name, scale: 1).first
                  size_bytes = (stats['size'] || stats['storageSize'] || stats['totalSize']).to_i rescue nil
                rescue StandardError
                  size_bytes = nil
                end
                # Try to get last activity based on common timestamp fields
                begin
                  doc = col.find({}, { sort: { updated_at: -1 }, projection: { updated_at: 1 } }).limit(1).first
                  if doc && doc['updated_at']
                    last_at = doc['updated_at'].respond_to?(:iso8601) ? doc['updated_at'].iso8601 : doc['updated_at'].to_s
                  else
                    doc = col.find({}, { sort: { created_at: -1 }, projection: { created_at: 1 } }).limit(1).first
                    if doc && doc['created_at']
                      last_at = doc['created_at'].respond_to?(:iso8601) ? doc['created_at'].iso8601 : doc['created_at'].to_s
                    else
                      doc = col.find({}, { sort: { timestamp: -1 }, projection: { timestamp: 1 } }).limit(1).first
                      if doc && doc['timestamp']
                        last_at = doc['timestamp'].respond_to?(:iso8601) ? doc['timestamp'].iso8601 : doc['timestamp'].to_s
                      end
                    end
                  end
                rescue StandardError
                  last_at = nil
                end
                details << { name: name, rows: docs.to_i, size_bytes: size_bytes, last_at: last_at }
              rescue StandardError => e
                details << { name: name, error: e.message }
              end
            end
            out[:collections] = details
          rescue StandardError => e
            out[:error] = e.message
          end
          out
        end

        # --- Reasoning API diagnostics ---
        def reasoning_diagnostics
          require 'time'
          require 'json'
          reasoning = {
            architecture: 'worker-based',
            redis: 'disconnected',
            workers: [],
            queue_length: 0,
            running_jobs: 0,
            dashboard_url: '/engine/jobs',
            workers_url: '/engine/workers',
            configured: true
          }

          # Check Redis connectivity and collect stats
          begin
            require 'redis'
            redis_url = ENV['REDIS_URL'] || 'redis://localhost:6379/0'
            r = ::Redis.new(url: redis_url, timeout: 1.0)
            r.ping
            reasoning[:redis] = 'connected'

            # Collect worker heartbeats
            worker_keys = r.keys('savant:workers:heartbeat:*')
            reasoning[:workers] = worker_keys.map do |k|
              name = k.split(':').last
              last_seen = r.get(k).to_f
              status = Time.now.to_f - last_seen < 60 ? 'alive' : 'dead'
              { id: name, last_seen: Time.at(last_seen).utc.iso8601, status: status }
            end

            # Queue stats
            reasoning[:queue_length] = r.llen('savant:queue:reasoning')
            reasoning[:running_jobs] = r.scard('savant:jobs:running')

            # Recent jobs
            reasoning[:recent_completed] = r.lrange('savant:jobs:completed', 0, 9).map { |j| JSON.parse(j) rescue j }
            reasoning[:recent_failed] = r.lrange('savant:jobs:failed', 0, 9).map { |j| JSON.parse(j) rescue j }
          rescue LoadError
            reasoning[:redis] = 'missing gem'
          rescue Exception => e
            reasoning[:redis] = "error: #{e.class} - #{e.message}"
          end

          # Support legacy base_url/reachable fields for compatibility
          reasoning[:base_url] = ENV['REASONING_API_URL'] || 'http://127.0.0.1:9000'
          reasoning[:reachable] = reasoning[:redis] == 'connected'

          # Usage stats via Mongo logs (service = 'reasoning')
          if mongo_available? && (cli = mongo_client)
            begin
              col = cli['reasoning_logs']
              now = Time.now
              since_1h = now - 3600
              since_24h = now - 86_400
              calls_total = col.estimated_document_count rescue nil
              calls_1h = col.count_documents({ 'timestamp' => { '$gt' => since_1h } }) rescue nil
              calls_24h = col.count_documents({ 'timestamp' => { '$gt' => since_24h } }) rescue nil
              last_at = begin
                doc = col.find({}, { sort: { timestamp: -1 }, projection: { timestamp: 1 } }).limit(1).first
                doc && doc['timestamp'] ? (doc['timestamp'].respond_to?(:iso8601) ? doc['timestamp'].iso8601 : doc['timestamp'].to_s) : nil
              rescue StandardError
                nil
              end

              events = %w[agent_intent workflow_intent reasoning_timeout reasoning_post_error]
              by_event = {}
              events.each do |ev|
                by_event[ev] = col.count_documents({ 'event' => ev }) rescue nil
              end

              reasoning[:calls] = { total: calls_total, last_1h: calls_1h, last_24h: calls_24h, last_at: last_at, by_event: by_event }
            rescue StandardError => e
              reasoning[:calls] = { error: e.message }
            end
          end

          # Agents and runs from Postgres (best effort)
          begin
            agents_total = runs_total = runs_24h = nil
            last_run_at = nil
            if @db.table_exists?('agents')
              agents_total = @db.exec('SELECT COUNT(*) AS c FROM agents')[0]['c'].to_i rescue nil
            end
            if @db.table_exists?('agent_runs')
              runs_total = @db.exec('SELECT COUNT(*) AS c FROM agent_runs')[0]['c'].to_i rescue nil
              runs_24h = @db.exec("SELECT COUNT(*) AS c FROM agent_runs WHERE created_at > NOW() - interval '24 hours'")[0]['c'].to_i rescue nil
              last_run_at = @db.exec('SELECT MAX(created_at) AS m FROM agent_runs')[0]['m'] rescue nil
            end
            reasoning[:agents] = { total: agents_total, runs_total: runs_total, runs_24h: runs_24h, last_run_at: last_run_at }
          rescue StandardError => e
            reasoning[:agents] = { error: e.message }
          end

          reasoning
        end

        def secrets_info(base_path)
          secrets_path = if ENV['SAVANT_SECRETS_PATH'] && !ENV['SAVANT_SECRETS_PATH'].empty?
                           ENV['SAVANT_SECRETS_PATH']
                         else
                           root_candidate = File.join(base_path, 'secrets.yml')
                           cfg_candidate = File.join(base_path, 'config', 'secrets.yml')
                           File.file?(root_candidate) ? root_candidate : cfg_candidate
                         end

          info = {
            path: secrets_path,
            exists: File.file?(secrets_path)
          }

          return info unless info[:exists]

          begin
            require_relative '../../../framework/secret_store'
            raw = Savant::Framework::SecretStore.yaml_safe_read(secrets_path)
            users_hash = if raw.is_a?(Hash) && raw['users'].is_a?(Hash)
                           raw['users']
                         else
                           raw.is_a?(Hash) ? raw : {}
                         end
            user_keys = users_hash.is_a?(Hash) ? users_hash.keys.map(&:to_s) : []
            info[:users] = user_keys.length if user_keys.any?
            service_names = []
            if users_hash.is_a?(Hash)
              users_hash.each_value do |services|
                next unless services.is_a?(Hash)

                services.each_key do |svc|
                  service_names << svc.to_s
                end
              end
            end
            service_names.uniq!
            info[:services] = service_names.sort if service_names.any?
          rescue StandardError => e
            info[:error] = e.message
          end

          info
        end

        def llm_models_info
          registry = Savant::Llm::Registry.new(@db)
          entries = registry.list_models
          states = Hash.new(0)
          models = entries.map do |model|
            enabled = truthy?(model[:enabled])
            state = enabled ? 'enabled' : 'disabled'
            states[state] += 1
            {
              name: model[:display_name].to_s.strip.empty? ? model[:provider_model_id] : model[:display_name],
              provider_name: model[:provider_name],
              provider_model_id: model[:provider_model_id],
              context_window: model[:context_window],
              enabled: enabled,
              state: state,
              modality: decode_modality(model[:modality])
            }
          end
          providers = registry.list_providers.map do |provider|
            {
              name: provider[:name],
              provider_type: provider[:provider_type],
              status: provider[:status]
            }
          end
          { total: entries.size, running: states['enabled'], states: states, models: models, providers: providers }
        rescue StandardError => e
          { error: e.message }
        end

        def llm_runtime_info
          registry = Savant::Llm::Registry.new(@db)
          slm = (ENV['SLM_MODEL'] || Savant::LLM::DEFAULT_SLM).to_s
          entries = registry.list_models
          preferred = entries.find { |m| truthy?(m[:enabled]) } || entries.first
          llm_model = if preferred
                        preferred[:display_name].to_s.strip.empty? ? preferred[:provider_model_id] : preferred[:display_name]
                      else
                        (ENV['LLM_MODEL'] || Savant::LLM::DEFAULT_LLM).to_s
                      end
          provider = preferred&.dig(:provider_name) || Savant::LLM.default_provider_for(llm_model)
          { slm_model: slm, llm_model: llm_model, provider: provider }
        rescue StandardError => e
          { error: e.message }
        end

        def decode_modality(value)
          return [] if value.nil?
          return value if value.is_a?(Array)
          decoded = text_array_decoder.decode(value) rescue nil
          return decoded if decoded.is_a?(Array)
          value.to_s.delete('{}').split(',').map(&:strip).reject(&:empty?)
        end

        def text_array_decoder
          @text_array_decoder ||= PG::TextDecoder::Array.new(
            name: 'text[]',
            elements_type: PG::TextDecoder::String.new(name: 'text')
          )
        end

        def truthy?(value)
          case value
          when true then true
          when false, nil then false
          when Integer then value != 0
          when String
            v = value.strip.downcase
            return true if %w[true t 1 yes y].include?(v)
            return false if %w[false f 0 no n].include?(v)
            !v.empty?
          else
            !!value
          end
        end

        def build_cache
          cfg = Savant::Indexer::Config.new(Savant::Framework::Config.load(@settings_path))
          Savant::Indexer::Cache.new(cfg.cache_path)
        end
      end
    end
  end
end
