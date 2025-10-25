#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../logger'
require_relative '../mcp_dispatcher'
require 'fileutils'

module Savant
  module Transports
    # Stdio transport loops over stdin, writes to stdout.
    class Stdio
      def initialize(service: 'context', base_path: nil)
        @service = service
        @base_path = base_path || default_base_path
      end

      def start
        log = prepare_logger(@service, @base_path)
        log.info('=' * 80)
        log.info("start: mode=stdio service=#{@service} tools=loading")
        log.info("pwd=#{Dir.pwd}")
        log.info("settings_path=#{File.join(@base_path, 'config', 'settings.json')}")
        log.info("log_path=#{File.join(@base_path, 'logs', "#{@service}.log")}")

        $stdout.sync = true
        $stderr.sync = true
        $stdin.sync = true

        dispatcher = Savant::MCP::Dispatcher.new(service: @service, log: log)
        log.info('buffers synced, waiting for requests...')
        log.info('=' * 80)
        while (line = $stdin.gets)
          log.info("raw_input: #{line.strip[0..200]}")
          req, err_json = dispatcher.parse(line)
          if err_json
            warn(err_json)
            next
          end
          response_json = dispatcher.handle(req)
          puts response_json
        end
      rescue Interrupt
        log = Savant::Logger.new(component: 'mcp')
        log.info('shutdown from Interrupt')
      end

      private

      def default_base_path
        (if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
           ENV['SAVANT_PATH']
         else
           File.expand_path('../../..', __dir__)
         end)
      end

      def prepare_logger(service, base_path)
        log_dir = File.join(base_path, 'logs')
        FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)
        log_path = File.join(log_dir, "#{service}.log")
        log_io = File.open(log_path, 'a')
        log_io.sync = true
        Savant::Logger.new(component: 'mcp', out: log_io)
      end
    end
  end
end
