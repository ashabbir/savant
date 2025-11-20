# frozen_string_literal: true

require 'json'

module Savant
  module Middleware
    # Rack middleware that enforces `x-savant-user-id` and attaches it to env.
    class UserHeader
      HEADER = 'HTTP_X_SAVANT_USER_ID'

      def initialize(app)
        @app = app
      end

      def call(env)
        user = env[HEADER]
        if user.nil? || user.strip.empty?
          return [
            400,
            { 'Content-Type' => 'application/json' },
            [JSON.generate({ error: 'missing required header x-savant-user-id' })]
          ]
        end

        env['savant.user_id'] = user
        @app.call(env)
      end
    end
  end
end

