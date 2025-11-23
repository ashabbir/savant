#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'ops'

module Savant
  module Rules
    # Engine exposes rule catalog operations for MCP tools.
    class Engine
      def initialize
        @log = Savant::Logger.new(io: $stdout, json: true, service: 'rules')
        @ops = Savant::Rules::Ops.new
      end

      def server_info
        { name: 'rules', version: '1.1.0', description: 'Savant Rules MCP engine' }
      end

      def list(filter: nil)
        @ops.list(filter: filter)
      end

      def get(name:)
        @ops.get(name: name)
      end
    end
  end
end
