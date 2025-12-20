#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require_relative '../logging/logger'
require_relative '../logging/event_recorder'
require_relative '../framework/engine/runtime_context'

module Savant
  module Reasoning
    Intent = Struct.new(
      :intent_id, :tool_name, :tool_args, :finish, :final_text, :next_node, :action_type, :reasoning, :trace,
      keyword_init: true
    )

    class Client
      DEFAULT_BASE_URL = 'http://127.0.0.1:9000'
      DEFAULT_TIMEOUT_MS = (ENV['REASONING_API_TIMEOUT_MS'] || '5000').to_i
      DEFAULT_RETRIES = (ENV['REASONING_API_RETRIES'] || '2').to_i
      DEFAULT_VERSION = (ENV['REASONING_API_VERSION'] || 'v1').to_s
      # Default to Mongo transport unless explicitly overridden
      DEFAULT_TRANSPORT = (ENV['REASONING_TRANSPORT'] || 'mongo').to_s # 'mongo' or 'http'

      def initialize(base_url: nil, token: nil, timeout_ms: nil, retries: nil, version: nil, logger: nil, transport: nil) # rubocop:disable Metrics/ParameterLists
        @base_url = (base_url || ENV['REASONING_API_URL'] || DEFAULT_BASE_URL).to_s
        @token = (token || ENV['REASONING_API_TOKEN']).to_s
        @timeout_ms = (timeout_ms || DEFAULT_TIMEOUT_MS).to_i
        @retries = (retries || DEFAULT_RETRIES).to_i
        @version = (version || DEFAULT_VERSION).to_s
        @logger = logger || Savant::Logging::MongoLogger.new(service: 'reasoning')
        @transport = (transport || DEFAULT_TRANSPORT).to_s
        @recorder = Savant::Logging::EventRecorder.global
      end

      def available?
        !@base_url.to_s.empty?
      end

      def agent_intent(payload)
        started = Time.now
        res = if @transport == 'mongo'
                agent_intent_via_mongo(payload)
              else
                post_json('/agent_intent', payload)
              end
        dur = ((Time.now - started) * 1000).to_i
        goal = (payload.is_a?(Hash) ? payload[:goal_text] || payload['goal_text'] : nil).to_s
        @logger.info(event: 'agent_intent', duration_ms: dur, status: res[:status], goal_text: goal, tool_name: res[:tool_name], finish: res[:finish])
        record_event('agent_intent',
                     duration_ms: dur,
                     status: res[:status],
                     goal_text: goal,
                     tool_name: res[:tool_name],
                     tool_args: res[:tool_args],
                     reasoning: res[:reasoning],
                     finish: res[:finish],
                     final_text: res[:final_text],
                     intent_id: res[:intent_id])
        validate_agent_response!(res)
        Intent.new(
          intent_id: res[:intent_id],
          tool_name: res[:tool_name],
          tool_args: res[:tool_args] || {},
          finish: !!res[:finish],
          final_text: res[:final_text],
          reasoning: res[:reasoning],
          trace: res[:trace]
        )
      end

      def workflow_intent(payload)
        started = Time.now
        res = post_json('/workflow_intent', payload)
        dur = ((Time.now - started) * 1000).to_i
        @logger.info(event: 'workflow_intent', duration_ms: dur, status: res[:status])
        record_event('workflow_intent', duration_ms: dur, status: res[:status])
        validate_workflow_response!(res)
        Intent.new(
          intent_id: res[:intent_id],
          next_node: res[:next_node],
          action_type: res[:action_type],
          tool_name: res[:tool_name],
          tool_args: res[:tool_args] || {},
          finish: !!res[:finish],
          reasoning: res[:reasoning],
          trace: res[:trace]
        )
      end

      private

      # ---------------------
      # Mongo transport (queue) for intent requests
      # ---------------------
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
        return @mongo_client if defined?(@mongo_client) && @mongo_client

        begin
          base = ENV.fetch('MONGO_URI', "mongodb://#{ENV.fetch('MONGO_HOST', 'localhost:27017')}")
          db = mongo_db_name
          # If MONGO_URI already contains a DB path, use it as-is; otherwise append our env-selected DB
          if base =~ %r{^mongodb(\+srv)?:\/\/[^\/]+\/.+}
            conn_str = base
          else
            conn_str = "#{base}/#{db}"
          end
          @mongo_client = Mongo::Client.new(conn_str, server_selection_timeout: 1.5, connect_timeout: 1.5, socket_timeout: 2)
        rescue StandardError
          @mongo_client = nil
        end
        @mongo_client
      end

      def mongo_db_name
        env = ENV.fetch('SAVANT_ENV', ENV.fetch('RACK_ENV', ENV.fetch('RAILS_ENV', 'development')))
        env == 'test' ? 'savant_test' : 'savant_development'
      end

      def agent_intent_via_mongo(payload)
        cli = mongo_client
        raise StandardError, 'reasoning_mongo_unavailable' unless cli

        col = cli[:reasoning_queue]
        corr = payload.is_a?(Hash) && payload[:correlation_id] ? payload[:correlation_id].to_s : "agent-#{Time.now.to_i}-#{rand(100_000)}"
        doc = {
          type: 'agent_intent',
          correlation_id: corr,
          status: 'queued',
          payload: symbolize_json(payload),
          created_at: Time.now.utc,
          updated_at: nil,
          result: nil
        }
        id = col.insert_one(doc).inserted_id
        # Poll until result available or timeout
        deadline = Time.now + (@timeout_ms.to_f / 1000.0)
        loop do
          sleep 0.2
          d = begin
            col.find({ _id: id }).limit(1).first
          rescue StandardError
            nil
          end
          return d['result'].transform_keys { |k| k.to_s.downcase.to_sym } if d && d['status'] == 'done' && d['result'].is_a?(Hash)

          raise StandardError, 'timeout' if Time.now > deadline
        end
      end

      public

      def cancel(correlation_id: nil)
        cid = correlation_id&.to_s
        return { ok: false } if cid.nil? || cid.empty?
        return agent_cancel_via_mongo(cid) if @transport == 'mongo'

        begin
          post_json('/agent_intent_cancel', { correlation_id: cid })
          { ok: true }
        rescue StandardError
          { ok: false }
        end
      end

      def agent_cancel_via_mongo(correlation_id)
        cli = mongo_client
        return { ok: false } unless cli

        col = cli[:reasoning_queue]
        begin
          col.update_many({ type: 'agent_intent', correlation_id: correlation_id.to_s, status: { '$in' => %w[queued processing] } }, { '$set' => { status: 'canceled', updated_at: Time.now.utc } })
          { ok: true }
        rescue StandardError
          { ok: false }
        end
      end

      def post_json(path, body)
        raise StandardError, 'reasoning_api_not_configured' if @base_url.to_s.empty?

        uri = URI.join(@base_url, path)
        headers = {
          'Content-Type' => 'application/json',
          'Accept' => 'application/json',
          'Accept-Version' => @version
        }
        headers['Authorization'] = "Bearer #{@token}" unless @token.to_s.empty?

        attempt = 0
        begin
          attempt += 1
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == 'https')
          http.read_timeout = (@timeout_ms.to_f / 1000.0)
          req = Net::HTTP::Post.new(uri.request_uri, headers)
          req.body = JSON.generate(symbolize_json(body))
          res = http.request(req)
          raise Net::ReadTimeout, 'timeout' if res.nil?

          code = res.code.to_i
          if code >= 500
            raise StandardError, "server_error: #{code}"
          elsif code >= 400
            msg = safe_parse_json(res.body) || {}
            raise StandardError, (msg[:error] || msg[:message] || "http_#{code}")
          end

          safe_parse_json(res.body)
        rescue Net::ReadTimeout, Net::OpenTimeout => e
          @logger.warn(event: 'reasoning_timeout', attempt: attempt, error: e.message)
          record_event('reasoning_timeout', attempt: attempt, error: e.message)
          retry if attempt <= @retries
          raise StandardError, 'timeout'
        rescue StandardError => e
          @logger.warn(event: 'reasoning_post_error', attempt: attempt, error: e.message)
          record_event('reasoning_post_error', attempt: attempt, error: e.message)
          retry if attempt <= @retries
          raise
        end
      end

      def record_event(name, extra = {})
        ev = { mcp: 'reasoning', event: name, ts: Time.now.utc.iso8601 }
        extra.each { |k, v| ev[k.to_sym] = v }
        @recorder.record(ev)
      rescue StandardError
        # ignore recorder failures
      end

      def validate_agent_response!(res)
        return unless res.is_a?(Hash)

        # Validate tool name if provided
        tool = (res[:tool_name] || '').to_s
        return if tool.empty?

        return if tool_available?(tool)

        raise StandardError, "intent_validation_error: invalid_tool #{tool}"
      end

      def validate_workflow_response!(_res)
        # Placeholder for future checks
        true
      end

      def tool_available?(name)
        mux = Savant::Framework::Runtime.current&.multiplexer
        return true unless mux # if no runtime, do not block

        names = mux.tools.map { |t| (t[:name] || t['name']).to_s }
        names.include?(name)
      rescue StandardError
        true
      end

      def safe_parse_json(body)
        JSON.parse(body.to_s, symbolize_names: true)
      rescue StandardError
        {}
      end

      def symbolize_json(obj)
        return obj unless obj.is_a?(Hash)

        obj.each_with_object({}) do |(k, v), h|
          h[k.to_sym] = v.is_a?(Hash) ? symbolize_json(v) : v
        end
      end
    end
  end
end
