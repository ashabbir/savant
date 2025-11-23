# frozen_string_literal: true

require 'rack'

module Savant
  module HTTP
    # Minimal static file server for the Hub UI under /ui.
    # Serves index.html for directory root.
    class StaticUI
      def initialize(root:)
        @root = root.to_s
      end

      def call(env)
        path = (env['PATH_INFO'] || '/').to_s
        file = resolve_file(path)
        # SPA fallback: serve index.html for unknown subpaths without extension
        unless file
          unless File.extname(path).to_s.include?('.')
            idx = File.join(@root, 'index.html')
            return serve_file(idx) if File.file?(idx)
          end
          return not_found
        end
        serve_file(file)
      rescue StandardError
        not_found
      end

      private

      def resolve_file(path)
        clean = path.sub(%r{^/+}, '')
        clean = 'index.html' if clean.empty? || clean == '/'
        candidate = File.join(@root, clean)
        if File.directory?(candidate)
          index = File.join(candidate, 'index.html')
          return index if File.file?(index)
        end
        return candidate if File.file?(candidate)

        nil
      end

      def serve_file(f)
        mime = Rack::Mime.mime_type(File.extname(f), 'text/plain')
        [200, { 'Content-Type' => mime }, [File.binread(f)]]
      end

      def not_found
        [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
      end
    end
  end
end
