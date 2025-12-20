#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'time'

module Savant
  module Logging
    # MongoDB Logger for MCP engine logs.
    #
    # Provides dual-output logging: writes to MongoDB collection AND stdio.
    # Each MCP engine (hub, personas, drivers, rules, think, context, agents)
    # gets its own collection for isolated log storage.
    #
    # Usage:
    #   logger = MongoLogger.new(service: 'think', collection: 'think_logs')
    #   logger.info(event: 'workflow_started', workflow: 'code_review')
    #
    class MongoLogger
      LEVELS = %w[trace debug info warn error].freeze

      attr_reader :service, :collection_name

      def initialize(service:, collection: nil, level: :info, db_name: nil, io: $stdout, json_stdio: true)
        @service = service.to_s
        @collection_name = collection || "#{@service}_logs"
        @level = level.to_s
        @db_name = db_name || mongo_db_name
        @io = io
        @json_stdio = json_stdio
        @mongo_client = nil
        @collection = nil
        @disable_mongo_logs = env_truthy(ENV['LOG_DISABLE_MONGO']) || env_truthy(ENV['DISABLE_MONGO_LOGGER']) || (
          env_truthy(ENV['SAVANT_DEV']) && !env_truthy(ENV['LOG_ENABLE_MONGO'])
        )
        @mongo_disabled_until = nil
        @consecutive_errors = 0
        @last_warn_at = 0
      end

      def level_enabled?(lvl)
        LEVELS.index(lvl.to_s) >= LEVELS.index(@level)
      end

      %w[trace debug info warn error].each do |lvl|
        define_method(lvl) do |payload = {}|
          return unless level_enabled?(lvl)

          log(lvl, payload)
        end
      end

      def with_timing(label: nil)
        start = current_time_ms
        result = yield
        dur = current_time_ms - start
        trace(event: label || 'timing', duration_ms: dur)
        [result, dur]
      end

      private

      def log(level, payload)
        timestamp = Time.now.utc
        base = {
          timestamp: timestamp.iso8601(3),
          level: level,
          service: @service
        }
        data = base.merge(symbolize_keys(payload))

        # Write to stdio
        write_to_stdio(data)

        # Write to MongoDB (best effort with backoff; skip if disabled)
        write_to_mongo(data, timestamp)
      end

      def write_to_stdio(data)
        return unless @io

        line = if @json_stdio
                 JSON.generate(data)
               else
                 format_text(data)
               end
        @io.puts(line)
        @io.flush if @io.respond_to?(:flush)
      rescue StandardError
        # Ignore stdio errors
      end

      def write_to_mongo(data, timestamp)
        return if @disable_mongo_logs
        return unless mongo_available?
        if @mongo_disabled_until && Time.now < @mongo_disabled_until
          return
        end

        doc = data.transform_keys(&:to_s)
        doc['timestamp'] = timestamp # Store as BSON Date for indexing
        collection.insert_one(doc)
        @consecutive_errors = 0
      rescue StandardError => e
        # Backoff after repeated errors to avoid flooding stdout and thread pool pressure
        @consecutive_errors += 1
        if @consecutive_errors >= 3
          @mongo_disabled_until = Time.now + 30 # 30s circuit-breaker
          @consecutive_errors = 0
        end
        now = Time.now.to_f
        if @io && (now - @last_warn_at) >= 5.0
          warn "MongoLogger: Failed to write to MongoDB: #{e.message}"
          @last_warn_at = now
        end
      end

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

      def mongo_client
        return nil unless mongo_available?

        @mongo_client ||= begin
          # Connect to local MongoDB (no auth by default for local dev)
          # Set MONGO_URI for custom connection string
          uri = ENV.fetch('MONGO_URI', "mongodb://#{mongo_host}/#{@db_name}")
          Mongo::Client.new(
            uri,
            server_selection_timeout: 1.0,
            connect_timeout: 1.0,
            socket_timeout: 2.0,
            max_pool_size: (ENV['MONGO_LOGGER_POOL'] || '5').to_i,
            wait_queue_timeout: 0.5
          )
        rescue StandardError
          nil
        end
      end

      def collection
        return nil unless mongo_client

        @collection ||= mongo_client[@collection_name]
      end

      def mongo_host
        ENV.fetch('MONGO_HOST', 'localhost:27017')
      end

      def mongo_db_name
        env = ENV.fetch('SAVANT_ENV', ENV.fetch('RACK_ENV', ENV.fetch('RAILS_ENV', 'development')))
        env == 'test' ? 'savant_test' : 'savant_development'
      end

      def env_truthy(v)
        return false if v.nil?
        %w[1 true yes on].include?(v.to_s.strip.downcase)
      end

      def symbolize_keys(payload)
        return {} if payload.nil?

        if payload.is_a?(Hash)
          payload.transform_keys { |k| k.is_a?(String) ? k.to_sym : k }
        else
          { message: payload.to_s }
        end
      end

      def format_text(data)
        msg = data[:message] || data[:event] || ''
        "#{data[:timestamp]} [#{data[:level].to_s.upcase}] #{data[:service]}: #{msg}"
      end

      def current_time_ms
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
      end
    end
  end
end
