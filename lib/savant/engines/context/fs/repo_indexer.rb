#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Expose repository indexing under the Context::FS namespace.

require_relative '../../indexer'
require_relative '../../../framework/db'
require_relative '../../../framework/config'
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
                # Detailed per-table stats for UI table
                begin
                  tables = %w[repos files blobs file_blob_map chunks personas rulesets agents agent_runs]
                  details = []
                  tables.each do |t|
                    cols = conn.exec_params("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=$1", [t]).map { |r| r['column_name'] }
                    cnt = conn.exec("SELECT COUNT(*) AS c FROM #{t}")[0]['c'].to_i
                    sz = conn.exec_params('SELECT pg_total_relation_size($1::regclass) AS bytes', [t])[0]['bytes'].to_i
                    last_at = nil
                    last_at = conn.exec("SELECT MAX(updated_at) AS m FROM #{t}")[0]['m'] if cols.include?('updated_at')
                    last_at = conn.exec("SELECT MAX(created_at) AS m FROM #{t}")[0]['m'] if !last_at && cols.include?('created_at')
                    details << { name: t, rows: cnt, size_bytes: sz, last_at: last_at }
                  rescue StandardError => e
                    details << { name: t, error: e.message }
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

          # Common mount points
          info[:mounts] = {
            '/app' => File.directory?('/app'),
            '/host' => File.directory?('/host'),
            '/host-crawler' => File.directory?('/host-crawler')
          }

          info[:llm_models] = llm_models_info
          info[:llm_runtime] = llm_runtime_info

          info[:secrets] = secrets_info(base)

          info
        end

        public :diagnostics

        private

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
          models = Savant::LLM::Ollama.models
          normalized = models.is_a?(Array) ? models : []

          # Overlay running status from /api/ps
          begin
            running_list = Savant::LLM::Ollama.ps
            running_names = running_list.map { |m| (m['name'] || m['model']).to_s }.to_set
          rescue StandardError
            running_names = Set.new
          end

          counts = Hash.new(0)
          running = 0
          normalized.each do |model|
            name = (model['name'] || model['model']).to_s
            if running_names.include?(name)
              model['running'] = true
              model['status'] ||= 'running'
            end
            state_label = llm_model_state(model)
            key = state_label.downcase.empty? ? 'unknown' : state_label.downcase
            counts[key] += 1
            running += 1 if llm_model_running?(model, key)
          end
          { total: normalized.size, running: running, states: counts, models: normalized }
        rescue StandardError => e
          { error: e.message }
        end

        def llm_runtime_info
          # Prefer hub runtime snapshot if available
          begin
            base = Dir.pwd
            runtime_path = File.join(base, '.savant', 'runtime.json')
            if File.file?(runtime_path)
              raw = begin
                JSON.parse(File.read(runtime_path))
              rescue StandardError
                {}
              end
              slm = (raw['slm_model'] || ENV['SLM_MODEL'] || Savant::LLM::DEFAULT_SLM).to_s
              llm = (raw['llm_model'] || ENV['LLM_MODEL'] || Savant::LLM::DEFAULT_LLM).to_s
              prov_val = raw['provider']
              provider = if prov_val.nil? || prov_val.to_s.strip.empty?
                           Savant::LLM.default_provider_for(llm)
                         else
                           prov_val.to_s.strip.to_sym
                         end
              return { slm_model: slm, llm_model: llm, provider: provider }
            end
          rescue StandardError
            # Fall through to defaults below
          end

          slm = (ENV['SLM_MODEL'] || Savant::LLM::DEFAULT_SLM).to_s
          llm = (ENV['LLM_MODEL'] || Savant::LLM::DEFAULT_LLM).to_s
          { slm_model: slm, llm_model: llm, provider: Savant::LLM.default_provider_for(llm) }
        rescue StandardError => e
          { error: e.message }
        end

        def llm_model_state(model)
          s = (model['state'] || model['status']).to_s.strip
          s.empty? ? 'installed' : s
        end

        def llm_model_running?(model, state_key)
          running_flag = model['running']
          return true if running_flag == true || running_flag.to_s.downcase == 'true'

          state_key.to_s == 'running'
        end

        def build_cache
          cfg = Savant::Indexer::Config.new(Savant::Framework::Config.load(@settings_path))
          Savant::Indexer::Cache.new(cfg.cache_path)
        end
      end
    end
  end
end
