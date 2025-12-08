# frozen_string_literal: true

# Ensure the parent repo's lib directory is on the load path
parent_lib = File.expand_path('../../../lib', __dir__)
$LOAD_PATH.unshift(parent_lib) unless $LOAD_PATH.include?(parent_lib)

require 'savant/hub/builder'

module SavantRails
  class SavantContainer
    class << self
      def base_path
        # Parent repo root (Rails app lives in server/)
        File.expand_path('../../..', __dir__)
      end

      # Full Hub Rack app (Router + Static UI) from Savant
      def hub_app
        @hub_app ||= Savant::Hub::Builder.build_from_config(base_path: base_path)
      end

      # Underlying service manager routing inside the Hub app when needed
      def service_manager
        # Obtain the manager through the hub app routes if exposed; otherwise build anew
        @service_manager ||= begin
          Savant::Hub::Builder.build_from_config(base_path: base_path) # returns composed app
        end
      end
    end
  end
end
