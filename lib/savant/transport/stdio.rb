# frozen_string_literal: true

require_relative 'base'

module Savant
  module Transport
    # Helper for stdio transport components to access the shared service manager.
    module STDIO
      module_function

      def service_manager(logger: nil, service: nil)
        ServiceManager.new(service: service || ENV['MCP_SERVICE'] || 'context', logger: logger)
      end
    end
  end
end
