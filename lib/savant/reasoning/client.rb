#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require_relative '../logging/logger'
require_relative '../framework/engine/runtime_context'

module Savant
  module Reasoning
    Intent = Struct.new(
      :intent_id, :tool_name, :tool_args, :finish, :final_text, :next_node, :action_type, :reasoning, :trace,
      keyword_init: true
    )

    class Client
      DEFAULT_TIMEOUT_MS = (ENV['REASONING_API_TIMEOUT_MS'] || '5000').to_i
      DEFAULT_RETRIES = (ENV['REASONING_API_RETRIES'] || '2').to_i
      DEFAULT_VERSION = (ENV['REASONING_API_VERSION'] || 'v1').to_s

      def initialize(base_url: nil, token: nil, timeout_ms: nil, retries: nil, version: nil, logger: nil)
        @base_url = (base_url || ENV['REASONING_API_URL'] || '').to_s
        @token = (token || ENV['REASONING_API_TOKEN']).to_s
        @timeout_ms = (timeout_ms || DEFAULT_TIMEOUT_MS).to_i
        @retries = (retries || DEFAULT_RETRIES).to_i
        @version = (version || DEFAULT_VERSION).to_s
        @logger = logger || Savant::Logging::MongoLogger.new(service: 'reasoning')
      end

      def available?
        !@base_url.to_s.empty?
      end

      def agent_intent(payload)
        started = Time.now
        res = post_json('/agent_intent', payload)
        dur = ((Time.now - started) * 1000).to_i
        @logger.info(event: 'agent_intent', duration_ms: dur, status: res[:status])
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
          retry if attempt <= @retries
          raise StandardError, 'timeout'
        rescue StandardError => e
          @logger.warn(event: 'reasoning_post_error', attempt: attempt, error: e.message)
          retry if attempt <= @retries
          raise
        end
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
