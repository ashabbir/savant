# frozen_string_literal: true

require 'fileutils'
require 'shellwords'
require_relative 'multiplexer/router'
require_relative 'multiplexer/engine_process'
require_relative 'framework/config'
require_relative 'logging/logger'

module Savant
  class Multiplexer
    class ToolNotFound < StandardError; end
    class EngineOffline < StandardError; end

    attr_reader :logger

    class << self
      attr_reader :global
    end

    def self.ensure!(**opts)
      return nil if ENV['SAVANT_MULTIPLEXER_DISABLED'] == '1'

      @global ||= new(**opts).tap(&:start)
    end

    def initialize(base_path: nil, settings_path: nil, logger: nil)
      @base_path = base_path || default_base_path
      @settings_path = settings_path || File.join(@base_path, 'config', 'settings.json')
      FileUtils.mkdir_p(File.join(@base_path, 'logs'))
      level = ENV['LOG_LEVEL'] || 'error'
      stdout_enabled = ENV['SAVANT_QUIET'] != '1'
      io = stdout_enabled ? $stdout : nil
      @logger = logger || Savant::Logging::Logger.new(io: io, file_path: File.join(@base_path, 'logs', 'multiplexer.log'), json: true, service: 'multiplexer', level: level)
      @router = Savant::Multiplexer::Router.new
      @engines = {}
      @mutex = Mutex.new
      @started = false
      @supervisor = nil
    end

    def start
      return self if @started

      configs = engine_configs
      configs.each { |cfg| spawn_engine(cfg) }
      start_supervisor
      @started = true
      @started_at = Time.now
      at_exit { shutdown }
      self
    end

    def shutdown
      @mutex.synchronize do
        @engines.each_value do |entry|
          entry[:process].stop!
        rescue StandardError => e
          @logger.warn(event: 'engine_stop_error', engine: entry[:name], error: e.message)
        end
      end
      @supervisor&.kill
      @supervisor = nil
    end

    def tools
      @router.tools
    end

    def call(name, args)
      entry = @router.lookup(name)
      raise ToolNotFound, name unless entry

      process = engine_process(entry[:engine])
      raise EngineOffline, entry[:engine] unless process&.online?

      process.call_tool(entry[:tool], args)
    end

    def engines
      @mutex.synchronize do
        @engines.transform_values { |entry| entry[:process].snapshot }
      end
    end

    def snapshot
      info = engines
      total = info.size
      online = info.count { |_, s| s[:status] == :online }
      offline = total - online
      tool_count = tools.count
      {
        status: if online.zero?
                  'offline'
                else
                  offline.positive? ? 'degraded' : 'online'
                end,
        engines: total,
        online: online,
        offline: offline,
        tools: tool_count,
        routes: tool_count,
        uptime_seconds: uptime_seconds,
        log_path: File.join(@base_path, 'logs', 'multiplexer.log')
      }
    end

    def server_info
      {
        protocolVersion: '2024-11-05',
        serverInfo: { name: 'savant-multiplexer', version: '1.0.0' },
        capabilities: { tools: {} },
        instructions: 'Unified Savant MCP multiplexer'
      }
    end

    private

    def start_supervisor
      @supervisor = Thread.new do
        loop do
          sleep 5
          supervise_once
        end
      end
    end

    def supervise_once
      @mutex.synchronize do
        @engines.each do |name, entry|
          proc = entry[:process]
          next if proc.online? || proc.running?

          begin
            @logger.warn(event: 'engine_restart', engine: name)
            proc.start!
            @router.register(name, proc.tools)
          rescue StandardError => e
            @logger.error(event: 'engine_restart_failed', engine: name, error: e.message)
          end
        end
      end
    end

    def engine_process(name)
      @mutex.synchronize { @engines[name]&.dig(:process) }
    end

    def spawn_engine(cfg)
      name = cfg[:name]
      return if name.to_s.empty?

      command = normalize_command(cfg[:command])
      env = cfg[:env] || {}
      process = Savant::Multiplexer::EngineProcess.new(
        name: name,
        base_path: @base_path,
        command: command,
        env: env,
        logger: @logger,
        on_status_change: method(:handle_status)
      )
      @mutex.synchronize { @engines[name] = { config: cfg, process: process } }
      return unless cfg[:autostart]

      process.start!
      @router.register(name, process.tools)
    rescue StandardError => e
      @logger.error(event: 'engine_spawn_failed', engine: name, error: e.message)
      @router.remove(name)
    end

    def handle_status(process, new_status, error)
      if new_status == :online
        @router.register(process.name, process.tools)
        @logger.info(event: 'engine_online', engine: process.name, pid: process.pid)
      else
        @router.remove(process.name)
        @logger.warn(event: 'engine_offline', engine: process.name, error: error)
      end
    end

    def engine_configs
      settings = load_settings
      raw = settings.dig('mcp', 'multiplexer', 'engines')
      configs = if raw.is_a?(Array) && raw.any?
                  raw
                else
                  default_engines
                end
      configs.map do |cfg|
        name = fetch(cfg, 'name')
        {
          name: name&.to_s,
          command: fetch(cfg, 'command'),
          env: fetch(cfg, 'env') || {},
          autostart: fetch(cfg, 'autostart', default: true)
        }
      end
    end

    def default_engines
      %w[context git think personas rules jira].map { |name| { name: name, autostart: true } }
    end

    def load_settings
      Savant::Framework::Config.load(@settings_path)
    rescue StandardError
      {}
    end

    def fetch(hash, key, default: nil)
      if hash.key?(key)
        hash[key]
      elsif hash.key?(key.to_sym)
        hash[key.to_sym]
      else
        default
      end
    end

    def default_base_path
      return ENV['SAVANT_PATH'] if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?

      File.expand_path('../..', __dir__)
    end

    def uptime_seconds
      return 0 unless @started

      @started_at ||= Time.now
      (Time.now - @started_at).to_i
    end

    def normalize_command(cmd)
      return nil unless cmd
      return cmd if cmd.is_a?(Array)

      Shellwords.split(cmd.to_s)
    end
  end
end
