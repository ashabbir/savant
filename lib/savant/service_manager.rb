# frozen_string_literal: true

require 'fileutils'
require_relative 'logger'
require_relative 'logging/event_recorder'

module Savant
  class UnknownServiceError < StandardError; end
  class BadRequestError < StandardError; end

  # Shared service loader/dispatcher for Savant transports (stdio, HTTP, etc.).
  class ServiceManager
    attr_reader :service, :total_tool_calls, :last_seen
    attr_accessor :logger

    def initialize(service:, logger: nil)
      @service = service.to_s.empty? ? 'context' : service.to_s
      @logger = logger || default_file_logger
      @services = {}
      @total_tool_calls = 0
      @last_seen = nil
    end

    def call_tool(name, args, request_id: nil)
      tool = normalize_tool_name(name)
      with_tool_logging(tool, request_id, args) do
        ensure_service
        registrar.call(tool, args || {}, ctx: { engine: engine, request_id: request_id, logger: logger })
      end
    end

    def specs
      ensure_service
      registrar.specs
    end

    def service_info
      ensure_service
      if engine.respond_to?(:server_info)
        engine.server_info
      else
        { name: 'savant', version: '1.1.0', description: "Savant MCP service=#{service}" }
      end
    rescue StandardError => e
      log_error('service_info error', error: e)
      { name: 'savant', version: '1.1.0', description: "Savant MCP service=#{service} (unavailable)" }
    end

    private

    def registrar
      @services[service][:registrar]
    end

    def engine
      @services[service][:engine]
    end

    def ensure_service
      @services[service] ||= load_service(service)
    end

    def load_service(name)
      camel = camelize(name)
      require File.join(__dir__, name, 'engine')
      require File.join(__dir__, name, 'tools')

      mod = Savant.const_get(camel)
      engine = mod.const_get(:Engine).new
      registrar = mod.const_get(:Tools).build_registrar(engine)
      { engine: engine, registrar: registrar }
    rescue LoadError, NameError => e
      raise UnknownServiceError, "Unknown service #{name}: #{e.message}"
    end

    def log_info(message, meta = {})
      logger&.info(format_log(message, meta))
    end

    def log_error(message, meta = {})
      logger&.error(format_log(message, meta))
    end

    def format_log(message, meta)
      attrs = { service: service }.merge(meta).map do |key, value|
        next if value.nil?

        formatted = value.is_a?(StandardError) ? "#{value.class}: #{value.message}" : value
        "#{key}=#{formatted}"
      end.compact.join(' ')
      attrs.empty? ? message : "#{message} #{attrs}"
    end

    def normalize_tool_name(name)
      tool = name.to_s.strip
      raise BadRequestError, 'missing method name' if tool.empty?

      tool
    end

    def camelize(name)
      name.split(/[^a-zA-Z0-9]/).map do |segment|
        next '' if segment.nil? || segment.empty?

        segment[0].upcase + segment[1..]
      end.join
    end

    def with_tool_logging(tool, request_id, args)
      rec = Savant::Logging::EventRecorder.global
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @last_seen = Time.now.utc.iso8601
      @total_tool_calls += 1
      safe_args = begin
        # Avoid huge payloads: stringify and truncate
        str = args.nil? ? '' : args.to_s
        str.length > 500 ? "#{str[0, 500]}...[truncated]" : str
      rescue StandardError
        nil
      end
      rec.record(type: 'tool_call_started', mcp: service, tool: tool, request_id: request_id, args: safe_args)
      log_info('tool.call start', name: tool, request_id: request_id)
      yield
    rescue BadRequestError, UnknownServiceError
      raise
    rescue StandardError => e
      dur = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      rec.record(type: 'tool_call_error', mcp: service, tool: tool, request_id: request_id, duration_ms: dur, error: begin
        e.message
      rescue StandardError
        e.to_s
      end)
      log_error('tool.call error', name: tool, request_id: request_id, error: e)
      raise
    ensure
      dur = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      rec.record(type: 'tool_call_completed', mcp: service, tool: tool, request_id: request_id, duration_ms: dur, status: 'ok')
      log_info('tool.call finish', name: tool, request_id: request_id)
    end

    def default_file_logger
      base = ENV['SAVANT_LOG_PATH'] && !ENV['SAVANT_LOG_PATH'].empty? ? ENV['SAVANT_LOG_PATH'] : '/tmp/savant'
      FileUtils.mkdir_p(base)
      path = File.join(base, "#{service}.log")
      io = File.open(path, 'a')
      io.sync = true
      Savant::Logger.new(io: io, json: true, service: service)
    rescue StandardError
      # Fallback to stdout logger if file path is not writable
      Savant::Logger.new(io: $stdout, json: true, service: service)
    end
  end
end
