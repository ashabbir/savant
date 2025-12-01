# frozen_string_literal: true

require 'json'

module Savant
  module Framework
    module Middleware
      # Rack middleware that enforces `x-savant-user-id` and attaches it to env.
      class UserHeader
        HEADER = 'HTTP_X_SAVANT_USER_ID'
        # Allow unauthenticated GET access for read-only diagnostics endpoints so static links work
        ALLOWLIST = [
          %r{^/diagnostics/workflows$},
          %r{^/diagnostics/workflow_runs$},
          %r{^/diagnostics/workflows/trace$},
          %r{^/diagnostics/agent$},
          %r{^/diagnostics/agent/trace$},
          %r{^/diagnostics/agent/session$}
        ].freeze

        def initialize(app)
          @app = app
        end

        def call(env)
          user = (env[HEADER] || '').to_s
          req = nil
          if user.strip.empty?
            # Fallback to query param for browser SSE / simple clients
            begin
              req = Rack::Request.new(env)
              user = (req.params['x-savant-user-id'] || req.params['user'] || req.params['uid'] || '').to_s
            rescue StandardError
              user = ''
            end
          end

          if user.strip.empty?
            begin
              req ||= Rack::Request.new(env)
              if req.request_method == 'GET' && ALLOWLIST.any? { |re| re.match?(req.path_info) }
                env['savant.user_id'] = 'public'
                return @app.call(env)
              end
            rescue StandardError
              # ignore and fall through to 400
            end
            return [400, { 'Content-Type' => 'application/json' }, [JSON.generate({ error: 'missing required header x-savant-user-id' })]]
          end

          env['savant.user_id'] = user
          @app.call(env)
        end
      end
    end
  end
end
