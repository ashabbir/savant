#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../logger'
require_relative '../mcp_dispatcher'
require 'fileutils'
require_relative '../config'

module Savant
  module Transports
    # Stdio transport loops over stdin, writes to stdout.
    class Stdio
      def initialize(service: 'context', base_path: nil)
        @service = service
        @base_path = base_path || default_base_path
      end

      def start
        cfg = load_settings(@base_path)
        core_file = cfg.dig('logging', 'core_file_path')
        resolve_engine_file(cfg, @service)

        log = prepare_logger(@service, @base_path, file_path: core_file)
        log.info(event: 'boot', mode: 'stdio', service: @service, message: 'tools=loading')
        log.info(event: 'env', pwd: Dir.pwd, settings_path: File.join(@base_path, 'config', 'settings.json'))

        $stdout.sync = true
        $stderr.sync = true
        $stdin.sync = true

        dispatcher = Savant::MCP::Dispatcher.new(service: @service, log: log)
        log.info(event: 'ready', message: 'buffers synced, waiting for requests...')
        while (line = $stdin.gets)
          log.trace(event: 'raw_input', preview: line.strip[0..200])
          req, err_json = dispatcher.parse(line)
          if err_json
            warn(err_json)
            next
          end
          response_json = dispatcher.handle(req)
          puts response_json
        end
      rescue Interrupt
        log = Savant::Logger.new(io: $stdout, file_path: File.join(@base_path, 'logs', "#{@service}.log"), level: :info, json: true, service: @service)
        log.info(event: 'shutdown', reason: 'Interrupt')
      end

      private

      def default_base_path
        (if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
           ENV['SAVANT_PATH']
         else
           File.expand_path('../../..', __dir__)
         end)
      end

      def prepare_logger(service, _base_path, file_path: nil)
        Savant::Logger.new(io: $stdout, file_path: file_path, level: ENV['LOG_LEVEL'] || 'info', json: true, service: service)
      end

      def load_settings(base_path)
        settings_path = File.join(base_path, 'config', 'settings.json')
        Savant::Config.load(settings_path)
      rescue StandardError
        {}
      end

      def resolve_engine_file(cfg, service)
        ef = cfg.dig('logging', 'engine_file_path')
        return nil unless ef

        if ef.end_with?('/') || File.extname(ef).empty? && !File.exist?(ef)
          File.join(ef, "#{service}.log")
        else
          ef
        end
      end
    end
  end
end
