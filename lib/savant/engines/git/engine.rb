#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../version'
require_relative '../../logging/logger'
require_relative '../../framework/engine/engine'
require_relative 'ops'

module Savant
  module Git
    # Orchestrates Git tools and delegates to Ops.
    class Engine < Savant::Framework::Engine::Base
      attr_reader :logger

      def initialize
        super()
        @logger = Savant::Logging::MongoLogger.new(service: 'git.engine')
        @ops = Savant::Git::Ops.new
      end

      def repo_status(path: nil)
        @ops.repo_status(path: path)
      end

      def changed_files(staged: false, path: nil)
        @ops.changed_files(staged: staged, path: path)
      end

      def diff(staged: false, paths: nil)
        @ops.diff(staged: staged, paths: paths)
      end

      def hunks(staged: false, paths: nil)
        @ops.hunks(staged: staged, paths: paths)
      end

      def read_file(path:, at: 'worktree')
        @ops.read_file(path: path, at: at)
      end

      def file_context(path:, line: nil, before: 3, after: 3, at: 'worktree')
        @ops.file_context(path: path, line: line, before: before, after: after, at: at)
      end

      def server_info
        { name: 'savant-git', version: Savant::VERSION, description: 'Git MCP: repo_status, changed_files, diff, hunks, file_context, read_file' }
      end
    end
  end
end
