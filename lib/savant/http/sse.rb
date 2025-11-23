# frozen_string_literal: true

require 'json'
require 'rack/request'

module Savant
  module HTTP
    # Minimal SSE Rack app which can be embedded by the hub router.
    # It supports a testing flag `?once=1` to emit a single heartbeat and close.
    class SSE
      DEFAULT_HEARTBEAT_SECS = 10

      def initialize(heartbeat_interval: DEFAULT_HEARTBEAT_SECS)
        @heartbeat_interval = heartbeat_interval.to_f
      end

      def call(env)
        req = Rack::Request.new(env)
        headers = {
          'Content-Type' => 'text/event-stream',
          'Cache-Control' => 'no-cache',
          'X-Accel-Buffering' => 'no' # disable proxy buffering where supported
        }

        once = req.params.key?('once') && req.params['once'] != '0'

        body = Enumerator.new do |yielder|
          # Always send an initial heartbeat so clients can confirm connection
          yielder << format_event('heartbeat', {})
          return if once

          loop do
            sleep(@heartbeat_interval)
            yielder << format_event('heartbeat', {})
          end
        rescue StandardError
          # Silently stop on disconnect or errors; Rack will close the stream
        end

        [200, headers, body]
      end

      private

      def format_event(event, data)
        "event: #{event}\n" \
          "data: #{JSON.generate(data)}\n\n"
      end
    end
  end
end
