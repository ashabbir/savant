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
      :intent_id, :tool_name, :tool_args, :finish, :final_text, :next_node, :action_type, :reasoning, :trace, :llm_input, :llm_output,
      keyword_init: true
    )

    class Client
      DEFAULT_TRANSPORT = 'redis'
      DEFAULT_TIMEOUT_MS = (ENV['REASONING_TIMEOUT_MS'] || '60000').to_i
      DEFAULT_RETRIES = (ENV['REASONING_RETRIES'] || '2').to_i

      def initialize(_base_url: nil, _token: nil, timeout_ms: nil, retries: nil, _version: nil, logger: nil, _transport: nil) # rubocop:disable Metrics/ParameterLists
        # legacy args ignored
        @timeout_ms = (timeout_ms || DEFAULT_TIMEOUT_MS).to_i
        @retries = (retries || DEFAULT_RETRIES).to_i
        @logger = logger || Savant::Logging::MongoLogger.new(service: 'reasoning')
        @recorder = Savant::Logging::EventRecorder.global
      end

      def available?
        redis_available?
      end

      def agent_intent(payload)
        started = Time.now
        # Always use Redis
        res = agent_intent_via_redis(payload)

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
                     intent_id: res[:intent_id],
                     llm_input: res[:llm_input],
                     llm_output: res[:llm_output])
        validate_agent_response!(res)
        Intent.new(
          intent_id: res[:intent_id],
          tool_name: res[:tool_name],
          tool_args: res[:tool_args] || {},
          finish: !!res[:finish],
          final_text: res[:final_text],
          reasoning: res[:reasoning],
          trace: res[:trace],
          llm_input: res[:llm_input],
          llm_output: res[:llm_output]
        )
      end

      def workflow_intent(_payload)
        # Not implemented yet in Redis worker, stubbing
        raise StandardError, 'workflow_intent_not_implemented_via_redis'
      end

      def agent_intent_async(payload, callback_url:)
        raise StandardError, 'reasoning_callback_url_required' if callback_url.to_s.strip.empty?

        job_id = "agent-#{Time.now.to_i}-#{rand(100_000)}"

        # Prepare job payload
        job = {
          job_id: job_id,
          callback_url: callback_url,
          payload: symbolize_json(payload),
          created_at: Time.now.utc.iso8601
        }

        redis = redis_client
        raise StandardError, 'reasoning_redis_unavailable' unless redis

        # Persist meta for manual retry/debug (TTL)
        begin
          ttl = (ENV['REASONING_JOB_META_TTL'] || '3600').to_i
          redis.setex("savant:job:meta:#{job_id}", ttl, JSON.generate(job))
        rescue StandardError
          # ignore meta failures
        end

        redis.rpush('savant:queue:reasoning', JSON.generate(job))

        {
          status: 'accepted',
          job_id: job_id
        }
      end

      def agent_intent_async_wait(*_args, **_kwargs)
        # Not supported in new redis-only architecture without status polling API from Rails.
        # For MVP, assume caller uses sync agent_intent if they want to wait.
        raise StandardError, 'async_wait_not_supported'
      end

      private

      # ---------------------
      # Redis transport (queue)
      # ---------------------
      def redis_available?
        return @redis_available if defined?(@redis_available)

        begin
          require 'redis'
          @redis_available = true
        rescue LoadError
          @redis_available = false
        end
        @redis_available
      end

      def redis_client
        return nil unless redis_available?
        return @redis_client if defined?(@redis_client) && @redis_client

        begin
          url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
          @redis_client = ::Redis.new(url: url)
        rescue StandardError
          @redis_client = nil
        end
        @redis_client
      end

      def agent_intent_via_redis(payload)
        redis = redis_client
        raise StandardError, 'reasoning_redis_unavailable' unless redis

        job_id = "agent-#{Time.now.to_i}-#{rand(100_000)}"

        # Prepare job payload
        job = {
          job_id: job_id,
          payload: symbolize_json(payload),
          created_at: Time.now.utc.iso8601
        }

        # Push to Redis Queue (Right push for FIFO)
        begin
          ttl = (ENV['REASONING_JOB_META_TTL'] || '3600').to_i
          redis.setex("savant:job:meta:#{job_id}", ttl, JSON.generate(job))
        rescue StandardError
          # ignore meta failures
        end
        redis.rpush('savant:queue:reasoning', JSON.generate(job))

        # Wait for result written by worker.
        # Contract divergence observed: some workers SET result at "savant:result:<job_id>" (string),
        # while others RPUSH to a list for BLPOP. Prefer polling GET to support both.
        result_key = "savant:result:#{job_id}"
        deadline = @timeout_ms.zero? ? nil : Time.now + (@timeout_ms.to_f / 1000.0)
        result_json = nil

        # First, try a short BLPOP to support list-based workers without busy-waiting
        begin
          res = redis.blpop(result_key, timeout: 1)
          result_json = res && res[1]
        rescue StandardError
          # ignore blpop errors; fall back to GET polling
        end

        # Poll GET until timeout or found
        while result_json.nil?
          raw = redis.get(result_key)
          if raw
            result_json = raw
            break
          end
          raise StandardError, 'timeout' if deadline && Time.now > deadline

          sleep 0.2
        end

        # Parse result JSON
        result = JSON.parse(result_json, symbolize_names: true)

        raise StandardError, result[:error] || 'unknown_worker_error' if result[:status] == 'error'

        result
      end

      public

      def cancel(_correlation_id: nil)
        # Not persisted in Redis for Phase 1/2 cancel support, assuming ok
        { ok: true }
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
