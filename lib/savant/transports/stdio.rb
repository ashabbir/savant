#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../logger'
require_relative '../logging/event_recorder'
require_relative '../connections'
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
        # Prefer per-engine file path if provided; else default to logs/<service>.log
        engine_file = resolve_engine_file(cfg, @service)
        file_path = engine_file || core_file || File.join(@base_path, 'logs', "#{@service}.log")
        level = (cfg.dig('logging', 'level') || ENV['LOG_LEVEL'] || 'info').to_s
        fmt = (cfg.dig('logging', 'format') || ENV['LOG_FORMAT'] || 'json').to_s

        log = prepare_logger(@service, @base_path, file_path: file_path, level: level, format: fmt)
        log.info(event: 'boot', mode: 'stdio', service: @service, message: 'tools=loading')
        log.info(event: 'env', pwd: Dir.pwd, settings_path: File.join(@base_path, 'config', 'settings.json'))

        $stdout.sync = true
        $stderr.sync = true
        $stdin.sync = true
        # Force UTF-8 on stdio to avoid Encoding::UndefinedConversionError on US-ASCII terminals
        begin
          $stdout.set_encoding(Encoding::UTF_8, Encoding::UTF_8)
          $stderr.set_encoding(Encoding::UTF_8, Encoding::UTF_8)
          $stdin.set_encoding(Encoding::UTF_8, Encoding::UTF_8)
        rescue StandardError
          # Some environments may not support set_encoding on stdio; ignore
        end

        dispatcher = Savant::MCP::Dispatcher.new(service: @service, log: log)
        # Register a pseudo-connection for this stdio session
        conn_id = Savant::Connections.global.connect(type: 'stdio', mcp: @service, path: 'stdio', user_id: ENV['USER'] || nil)
        rec = Savant::Logging::EventRecorder.global
        log.info(event: 'ready', message: 'buffers synced, waiting for requests...')
        while (line = $stdin.gets)
          log.trace(event: 'raw_input', preview: line.strip[0..200])
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          rec.record(type: 'stdio_message', dir: 'in', mcp: @service, preview: line.strip[0..200])
          req, err_json = dispatcher.parse(line)
          if err_json
            warn(err_json)
            next
          end
          response_json = dispatcher.handle(req)
          dur = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
          rec.record(type: 'stdio_message', dir: 'out', mcp: @service, id: req['id'], method: req['method'], duration_ms: dur, bytes: response_json.to_s.bytesize)
          puts response_json
        end
      rescue Interrupt
        log = Savant::Logger.new(io: $stdout, file_path: File.join(@base_path, 'logs', "#{@service}.log"),
                                 level: :info, json: true, service: @service)
        log.info(event: 'shutdown', reason: 'Interrupt')
      ensure
        Savant::Connections.global.disconnect(conn_id) if defined?(conn_id) && conn_id
      end

      private

      def default_base_path
        (if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
           ENV['SAVANT_PATH']
         else
           File.expand_path('../../..', __dir__)
         end)
      end

      def prepare_logger(service, _base_path, file_path: nil, level: 'info', format: 'json')
        json = format.to_s.downcase != 'text'
        Savant::Logger.new(io: $stdout, file_path: file_path, level: level, json: json, service: service)
      end

      def load_settings(base_path)
        settings_path = File.join(base_path, 'config', 'settings.json')
        Savant::Config.load(settings_path)
      rescue StandardError
        {}
      end

      def resolve_engine_file(cfg, service)
        ef = cfg.dig('logging', 'engine_file_path')
        return nil unless ef && !ef.to_s.strip.empty?

        # If a directory is given (trailing slash or no extension and non-existent), append service filename
        if ef.end_with?('/') || (File.extname(ef).empty? && !File.exist?(ef))
          File.join(ef, "#{service}.log")
        else
          ef
        end
      end
    end
  end
end
