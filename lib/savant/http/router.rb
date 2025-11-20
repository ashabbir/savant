# frozen_string_literal: true

require 'json'
require 'rack/request'

require_relative '../middleware/user_header'
require_relative 'sse'

module Savant
  module HTTP
    # Lightweight hub router for multi-engine HTTP + SSE endpoints.
    class Router
      def self.build(mounts:, transport: 'http', heartbeat_interval: SSE::DEFAULT_HEARTBEAT_SECS)
        new(mounts: mounts, transport: transport, heartbeat_interval: heartbeat_interval)
      end

      def initialize(mounts:, transport:, heartbeat_interval: SSE::DEFAULT_HEARTBEAT_SECS)
        @mounts = mounts # { 'engine_name' => ServiceManager-like }
        @transport = transport
        @sse = SSE.new(heartbeat_interval: heartbeat_interval)
      end

      def call(env)
        Savant::Middleware::UserHeader.new(method(:dispatch)).call(env)
      end

      private

      attr_reader :mounts, :transport, :sse

      def dispatch(env)
        req = Rack::Request.new(env)
        return hub_root(req) if req.get? && req.path_info == '/'

        # Engine scoped routes: /:engine/...
        segments = req.path_info.split('/').reject(&:empty?)
        return not_found unless segments.size >= 1

        engine_name = segments[0]
        manager = mounts[engine_name]
        return not_found unless manager

        case req.request_method
        when 'GET'
          handle_get(req, engine_name, manager, segments[1..])
        when 'POST'
          handle_post(req, engine_name, manager, segments[1..])
        else
          not_found
        end
      rescue JSON::ParserError
        respond(400, { error: 'invalid JSON' })
      rescue StandardError => e
        respond(500, { error: 'internal error', message: e.message })
      end

      def handle_get(req, engine_name, manager, rest)
        case rest
        when ['tools']
          tools = manager.registrar.specs
          respond(200, { engine: engine_name, tools: tools })
        when ['status']
          info = manager.service_info
          uptime = manager.respond_to?(:uptime) ? manager.uptime : 0
          respond(200, { engine: engine_name, status: 'running', uptime_seconds: uptime, info: info })
        when ['logs']
          respond(200, { engine: engine_name, logs: [], note: 'not_implemented' })
        when ['stream']
          sse.call(req.env)
        else
          not_found
        end
      end

      def handle_post(req, engine_name, manager, rest)
        if rest.size == 3 && rest[0] == 'tools' && rest[2] == 'call'
          tool = rest[1]
          payload = parse_json_body(req)
          params = payload.is_a?(Hash) ? (payload['params'] || {}) : {}
          result = manager.registrar.call(tool, params, ctx: { engine: engine_name, user_id: req.env['savant.user_id'] })
          respond(200, result)
        else
          not_found
        end
      end

      def hub_root(_req)
        engines = mounts.map do |name, manager|
          tool_count = (manager.registrar.specs || []).size
          { name: name, path: "/#{name}", tools: tool_count, status: 'running', uptime_seconds: (manager.respond_to?(:uptime) ? manager.uptime : 0) }
        end
        payload = {
          service: 'Savant MCP Hub',
          version: '3.0.0',
          transport: transport,
          hub: { pid: Process.pid, uptime_seconds: uptime_seconds },
          engines: engines
        }
        respond(200, payload)
      end

      def uptime_seconds
        @started ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started).to_i
      end

      def parse_json_body(req)
        req.body.rewind if req.body.respond_to?(:rewind)
        raw = req.body.read.to_s
        req.body.rewind if req.body.respond_to?(:rewind)
        return {} if raw.empty?

        JSON.parse(raw)
      end

      def respond(status, body_hash)
        [status, { 'Content-Type' => 'application/json' }, [JSON.generate(body_hash)]]
      end

      def not_found
        respond(404, { error: 'not found' })
      end
    end
  end
end

