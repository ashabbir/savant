#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'yaml'
require 'fileutils'
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
      end

      def server_info
        {
          name: 'workflow',
          version: '0.1.0',
          description: 'Deterministic YAML workflow executor (tools + agents)'
        }
      end

      # Run a workflow to completion.
      # Returns { run_id:, final:, steps:, status: 'ok'|'error', error?: }
      def run(workflow:, params: {})
        spec = Loader.load(@base_path, workflow)
        run_id = generate_run_id(workflow)
        result, trace = Executor.new(base_path: @base_path, logger: @logger).run(spec: spec, params: params || {}, run_id: run_id)
        persist_state(workflow: workflow, run_id: run_id, state: trace)
        { run_id: run_id, final: result, steps: trace[:steps], status: trace[:status], error: trace[:error] }
      end

      # List saved runs
      def runs_list
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
        path = File.join(@runs_dir, "#{workflow}__#{run_id}.json")
        raise 'RUN_NOT_FOUND' unless File.file?(path)

        { state: JSON.parse(File.read(path)) }
      end

      def run_delete(workflow:, run_id:)
        path = File.join(@runs_dir, "#{workflow}__#{run_id}.json")
        if File.exist?(path)
          FileUtils.rm_f(path)
          { ok: true, deleted: true }
        else
          { ok: true, deleted: false }
        end
      end

      private

      def persist_state(workflow:, run_id:, state:)
        path = File.join(@runs_dir, "#{workflow}__#{run_id}.json")
        tmp = path + '.tmp'
        File.open(tmp, 'w:UTF-8') { |f| f.write(JSON.pretty_generate(state.merge(workflow: workflow, run_id: run_id))) }
        FileUtils.mv(tmp, path)
      rescue StandardError
        # best-effort persistence only
        nil
      end

      def generate_run_id(workflow)
        seed = "#{workflow}|#{Time.now.utc.to_i}|#{$$}|#{rand(1_000_000)}"
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
    end
  end
end
