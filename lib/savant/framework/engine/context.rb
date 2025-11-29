#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../logging/logger'
require_relative 'config/loader'

module Savant
  module Core
    # Shared runtime context made available to engines and tools.
    # Exposes logger and config; DB is optional and may be set by an engine.
    class Context
      attr_reader :logger, :config
      attr_accessor :db

      def initialize(logger: nil, config: nil, db: nil)
        @logger = logger || Savant::Logging::Logger.new(io: $stdout, json: true, service: 'savant.core')
        @config = config || Savant::Framework::Engine::Config::Loader.load
        @db = db
      end
    end
  end
end
