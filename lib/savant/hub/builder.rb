# frozen_string_literal: true

require 'yaml'
require 'rack'
require_relative 'router'
require_relative 'static_ui'
require_relative 'service_manager'
require_relative '../framework/secret_store'
require_relative '../multiplexer'

module Savant
  module Hub
    # Hub builder: loads engines and returns a Rack app.
    class Builder
      class << self
        def build_from_config(base_path: nil)
          base = base_path || (ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty? ? ENV['SAVANT_PATH'] : File.expand_path('../../..', __dir__))
          mounts_cfg = safe_load(File.join(base, 'config', 'mounts.yml'))
          transport_cfg = safe_load(File.join(base, 'config', 'transport.yml'))
          # Prefer explicit env, otherwise try repo root secrets.yml then config/secrets.yml
          secrets_path = if ENV['SAVANT_SECRETS_PATH'] && !ENV['SAVANT_SECRETS_PATH'].empty?
                           ENV['SAVANT_SECRETS_PATH']
                         else
                           root_candidate = File.join(base, 'secrets.yml')
                           cfg_candidate = File.join(base, 'config', 'secrets.yml')
                           File.file?(root_candidate) ? root_candidate : cfg_candidate
                         end
          begin
            require_relative '../framework/secret_store'
            Savant::Framework::SecretStore.load_file(secrets_path)
          rescue StandardError
            # ignore missing/invalid secrets file
          end

          transport_mode = (transport_cfg.dig('transport', 'mode') || 'http').to_s
          mounts = build_mounts(mounts_cfg, base_path: base)
          begin
            settings_path = File.join(base, 'config', 'settings.json')
            Savant::Multiplexer.ensure!(base_path: base, settings_path: settings_path)
          rescue StandardError
            # Multiplexer is optional for Hub startup; ignore failures
          end
          router = Savant::Hub::Router.build(mounts: mounts, transport: transport_mode)

          # Compose Rack app with static UI under /ui
          ui_root = File.join(base, 'public', 'ui')
          builder = Rack::Builder.new
          builder.map('/ui') { run Savant::Hub::StaticUI.new(root: ui_root) }
          builder.run router

          # Wrap the composed app to expose router metadata (for startup logs and CLI routes)
          ComposedHubApp.new(builder.to_app, router, ui_root)
        end

        def build_mounts(cfg, base_path: nil)
          entries = cfg['mounts'] || []
          mounts = entries.each_with_object({}) do |entry, h|
            name = entry['engine']
            next if name.to_s.empty?

            h[name] = Savant::Hub::ServiceManager.new(service: name)
          end

          return mounts unless mounts.empty?

          # Fallback: auto-discover engines under lib/savant/engines/*/engine.rb with tools.rb present
          begin
            lib_root = base_path ? File.join(base_path, 'lib', 'savant') : File.join(File.expand_path('../../..', __dir__), 'lib', 'savant')
            Dir.glob(File.join(lib_root, 'engines', '*', 'engine.rb')).each do |engine_rb|
              name = File.basename(File.dirname(engine_rb))
              tools_rb = File.join(File.dirname(engine_rb), 'tools.rb')
              next unless File.file?(tools_rb)

              mounts[name] = Savant::Hub::ServiceManager.new(service: name)
            end
          rescue StandardError
            # ignore discovery errors
          end
          mounts
        end

        def safe_load(path)
          return {} unless File.file?(path)

          YAML.safe_load(File.read(path)) || {}
        rescue StandardError
          {}
        end
      end
    end

    # Wrapper exposing metadata while delegating Rack calls to the composed app
    class ComposedHubApp
      def initialize(app, router, ui_root)
        @app = app
        @router = router
        @ui_root = ui_root
      end

      def call(env)
        @app.call(env)
      end

      def engine_overview
        @router.engine_overview
      end

      def routes(expand_tools: false)
        @router.routes(expand_tools: expand_tools)
      end

      attr_reader :ui_root
    end

    class << self
      def build_from_config(base_path: nil)
        Builder.build_from_config(base_path: base_path)
      end

      def build_mounts(cfg, base_path: nil)
        Builder.build_mounts(cfg, base_path: base_path)
      end
    end
  end
end
