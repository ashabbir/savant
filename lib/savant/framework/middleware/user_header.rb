# frozen_string_literal: true

require 'json'

module Savant
  module Framework
    module Middleware
      # Rack middleware that enforces `x-savant-user-id` and attaches it to env.
      class UserHeader
      HEADER = 'HTTP_X_SAVANT_USER_ID'

      def initialize(app)
        @app = app
      end

      def call(env)
        user = (env[HEADER] || '').to_s
        if user.strip.empty?
          # Fallback to query param for browser SSE / simple clients
          begin
            req = Rack::Request.new(env)
            user = (req.params['x-savant-user-id'] || req.params['user'] || req.params['uid'] || '').to_s
          rescue StandardError
            user = ''
          end
        end

        return [400, { 'Content-Type' => 'application/json' }, [JSON.generate({ error: 'missing required header x-savant-user-id' })]] if user.strip.empty?

        env['savant.user_id'] = user
        @app.call(env)
      end
      end
    end
  end
end
