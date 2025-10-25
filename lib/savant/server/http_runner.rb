# frozen_string_literal: true

require 'fileutils'
require 'rack'
require 'rack/handler/webrick'
require 'webrick'

require_relative '../logger'
require_relative '../transport/base'
require_relative '../transport/http'

module Savant
  module Server
    # Rack runner for the Savant HTTP transport.
    class HTTPRunner
      DEFAULT_PORT = 9292
      DEFAULT_HOST = '0.0.0.0'

      class << self
        def start(host: nil, port: nil, service: nil)
          base_path = resolve_base_path
          log_io = build_log_io(base_path)
          logger = build_logger(log_io)
          manager = build_manager(service, logger)

          run_server(manager, logger, host, port)
        ensure
          log_io&.close unless log_io&.closed?
        end

        private

        def run_server(manager, logger, host, port)
          app = Savant::Transport::HTTP.build(service_manager: manager, logger: logger)
          bind_host = resolve_host(host)
          bind_port = resolve_port(port)
          announce(logger, manager, bind_host, bind_port)
          Rack::Handler::WEBrick.run(app, **webrick_options(bind_host, bind_port))
        end

        def build_logger(io)
          Savant::Logger.new(component: 'http', out: io)
        end

        def build_manager(service, logger)
          service_name = (service || ENV['MCP_SERVICE'] || 'context').to_s
          Savant::Transport::ServiceManager.new(service: service_name, logger: logger)
        end

        def resolve_base_path
          base = (ENV['SAVANT_PATH'] || '').strip
          return base unless base.empty?

          File.expand_path('../../..', __dir__)
        end

        def resolve_host(override)
          override || ENV['SAVANT_HOST'] || ENV['LISTEN_HOST'] || DEFAULT_HOST
        end

        def resolve_port(override)
          Integer(override || ENV['SAVANT_PORT'] || ENV['LISTEN_PORT'] || DEFAULT_PORT)
        end

        def build_log_io(base_path)
          log_dir = File.join(base_path, 'logs')
          FileUtils.mkdir_p(log_dir)
          path = File.join(log_dir, 'http.log')
          io = File.open(path, 'a')
          io.sync = true
          io
        end

        def webrick_options(host, port)
          {
            Host: host,
            Port: port,
            AccessLog: [],
            Logger: WEBrick::Log.new(nil, 0)
          }
        end

        def announce(logger, manager, host, port)
          info = manager.service_info
          logger.info("start: host=#{host} port=#{port} service=#{manager.service}")
          logger.info("service_info name=#{info[:name]} version=#{info[:version]}")
        end
      end
    end
  end
end
