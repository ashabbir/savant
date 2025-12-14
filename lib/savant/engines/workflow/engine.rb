#!/usr/bin/env ruby
# frozen_string_literal: true

require 'English'
require 'json'
require 'yaml'
require 'fileutils'
begin
  require 'mongo'
rescue LoadError
end
require_relative '../../version'
require_relative 'executor'
require_relative 'loader'

module Savant
  module Workflow
    # Public API for Workflow engine
    class Engine
      def initialize(base_path: nil, logger: nil)
        @base_path = base_path || default_base_path
        @runs_dir = File.join(@base_path, '.savant', 'workflow_runs')
        FileUtils.mkdir_p(@runs_dir)
        @logger = logger || default_logger
        @mongo_client = init_mongo
      end

      def server_info
        {
          name: 'workflow',
          version: Savant::VERSION,
          description: 'Deterministic YAML workflow executor (tools + agents)'
        }
      end

      # List available workflows under workflows/*.yaml
      def workflows_list(filter: nil)
        dir = File.join(@base_path, 'workflows')
        rows = []
        if Dir.exist?(dir)
          Dir.glob(File.join(dir, '*.y{a,}ml')).each do |path|
            id = File.basename(path).sub(/\.(yaml|yml)$/i, '')
            next if filter && !id.include?(filter.to_s)

            rows << { id: id, path: path }
          end
        end
        { workflows: rows.sort_by { |r| r[:id] } }
      end

      # Run a workflow to completion.
      # Returns { run_id:, final:, steps:, status: 'ok'|'error', error?: }
      def run(workflow:, params: {})
        spec = Loader.load(@base_path, workflow)
        run_id = generate_run_id(workflow)
        result, trace = Executor.new(base_path: @base_path, logger: @logger).run(spec: spec, params: params || {}, run_id: run_id)
        persist_state(workflow: workflow, run_id: run_id, state: trace)
        persist_state_mongo(workflow: workflow, run_id: run_id, state: trace)
        { run_id: run_id, final: result, steps: trace[:steps], status: trace[:status], error: trace[:error] }
      end

      # List saved runs
      def runs_list
        # Try Mongo first
        if (col = workflow_runs_col)
          begin
            docs = col.find({}).sort({ updated_at: -1 }).limit(500).to_a
            rows = docs.map do |d|
              {
                workflow: d['workflow'] || d[:workflow],
                run_id: d['run_id'] || d[:run_id],
                steps: Array(d['steps'] || d[:steps]).size,
                status: d['status'] || d[:status] || 'unknown',
                updated_at: (d['updated_at'] || d[:updated_at]).is_a?(Time) ? (d['updated_at'] || d[:updated_at]).iso8601 : d['updated_at'] || d[:updated_at]
              }
            end
            return { runs: rows }
          rescue StandardError
            # fallback to filesystem
          end
        end

        rows = []
        Dir.children(@runs_dir).select { |f| f.end_with?('.json') }.each do |fn|
          path = File.join(@runs_dir, fn)
          begin
            st = JSON.parse(File.read(path))
            rows << {
              workflow: st['workflow'],
              run_id: st['run_id'],
              steps: Array(st['steps']).size,
              status: st['status'] || 'unknown',
              updated_at: File.mtime(path).utc.iso8601,
              path: path
            }
          rescue StandardError
            next
          end
        end
        { runs: rows.sort_by { |r| r[:updated_at] } }
      end

      def run_read(workflow:, run_id:)
        if (col = workflow_runs_col)
          begin
            d = col.find({ workflow: workflow, run_id: run_id }).limit(1).first
            if d
              state = d['state'] || d[:state]
              return { state: state.is_a?(Hash) ? state : JSON.parse(state.to_s) }
            end
          rescue StandardError
          end
        end
        path = File.join(@runs_dir, "#{workflow}__#{run_id}.json")
        raise 'RUN_NOT_FOUND' unless File.file?(path)

        { state: JSON.parse(File.read(path)) }
      end

      def run_delete(workflow:, run_id:)
        deleted = false
        if (col = workflow_runs_col)
          begin
            res = col.delete_many({ workflow: workflow, run_id: run_id })
            deleted ||= res.deleted_count.to_i > 0
          rescue StandardError
          end
        end
        path = File.join(@runs_dir, "#{workflow}__#{run_id}.json")
        if File.exist?(path)
          FileUtils.rm_f(path)
          deleted = true
        end
        { ok: true, deleted: deleted }
      end

      private

      def persist_state(workflow:, run_id:, state:)
        path = File.join(@runs_dir, "#{workflow}__#{run_id}.json")
        tmp = "#{path}.tmp"
        File.open(tmp, 'w:UTF-8') { |f| f.write(JSON.pretty_generate(state.merge(workflow: workflow, run_id: run_id))) }
        FileUtils.mv(tmp, path)
      rescue StandardError
        # best-effort persistence only
        nil
      end

      def persist_state_mongo(workflow:, run_id:, state:)
        return unless (col = workflow_runs_col)
        doc = {
          workflow: workflow,
          run_id: run_id,
          steps: state[:steps] || state['steps'] || [],
          status: state[:status] || state['status'] || 'unknown',
          updated_at: Time.now.utc,
          state: state
        }
        begin
          col.insert_one(doc)
        rescue StandardError
          # ignore
        end
      end

      def generate_run_id(workflow)
        seed = "#{workflow}|#{Time.now.utc.to_i}|#{$PROCESS_ID}|#{rand(1_000_000)}"
        "#{Time.now.utc.strftime('%Y%m%d%H%M%S')}-#{Digest::SHA256.hexdigest(seed)[0, 8]}"
      end

      def default_base_path
        if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
          ENV['SAVANT_PATH']
        else
          File.expand_path('../../../../..', __dir__)
        end
      end

      def default_logger
        require_relative '../../logging/logger'
        Savant::Logging::Logger.new(io: $stdout, file_path: File.join(@base_path, 'logs', 'workflow_engine.log'), json: true, service: 'workflow')
      end

      def init_mongo
        return nil unless defined?(Mongo)
        begin
          uri = ENV.fetch('MONGO_URI', "mongodb://#{mongo_host}/#{mongo_db_name}")
          client = Mongo::Client.new(uri, server_selection_timeout: 1.5, connect_timeout: 1.5, socket_timeout: 2)
          client.database.collections
          client
        rescue StandardError
          nil
        end
      end

      def workflow_runs_col
        @mongo_client ? @mongo_client[:workflow_runs] : nil
      end

      def mongo_host
        ENV.fetch('MONGO_HOST', 'localhost:27017')
      end

      def mongo_db_name
        env = ENV.fetch('SAVANT_ENV', ENV.fetch('RACK_ENV', ENV.fetch('RAILS_ENV', 'development')))
        env == 'test' ? 'savant_test' : 'savant_development'
      end
    end
  end
end
