#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'ops'

module Savant
  module Personas
    # Engine exposes personas catalog over MCP tools.
    class Engine
      def initialize
        @log = Savant::Logger.new(io: $stdout, json: true, service: 'personas')
        @ops = Savant::Personas::Ops.new
      end

      def server_info
        { name: 'personas', version: '1.1.0', description: 'Savant Personas MCP engine' }
      end

      # API used by Tools
      def list(filter: nil)
        @ops.list(filter: filter)
      end

      def get(name:)
        @ops.get(name: name)
      end
    end
  end
end
