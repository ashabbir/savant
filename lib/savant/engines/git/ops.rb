#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require_relative '../../logging/logger'
require_relative 'repo_detector'
require_relative 'diff_parser'
require_relative 'hunk_parser'
require_relative 'file_context'

module Savant
  module Git
    # Implements Git business logic behind the MCP tools.
    class Ops
      def initialize
        @log = Savant::Logging::MongoLogger.new(service: 'git.ops')
        @detector = Savant::Git::RepoDetector.new
      end

      def repo_status(path: nil)
        @detector.status(path: path)
      end

      def changed_files(staged: false, path: nil)
        root = ensure_root!(path)
        porcelain = staged ? '--porcelain --cached' : '--porcelain'
        cmd = %(git -C #{Shellwords.escape(root)} status #{porcelain})
        out, err, st = Open3.capture3(cmd)
        raise err.strip unless st.success?

        parse_status_porcelain(out)
      end

      def diff(staged: false, paths: nil)
        root = ensure_root!(nil)
        files = if paths && !paths.empty?
                  paths
                else
                  changed_files(staged: staged).map { |r| r[:path] }
                end
        return [] if files.empty?

        parser = Savant::Git::DiffParser.new
        files.map do |p|
          text = diff_for_file(root: root, path: p, staged: staged)
          entry = parser.parse_file_diff(text)
          status = changed_files(staged: staged).find { |r| r[:path] == p }&.dig(:status) || 'M'
          { path: p, status: status, hunks: entry[:hunks] }
        end
      end

      def hunks(staged: false, paths: nil)
        ds = diff(staged: staged, paths: paths)
        hp = Savant::Git::HunkParser.new
        ds.map do |file|
          { path: file[:path], status: file[:status], hunks: file[:hunks].map { |h| hp.extract(h) } }
        end
      end

      def read_file(path:, at: 'worktree')
        root = ensure_root!(nil)
        Savant::Git::FileContext.read_file(root: root, path: path, at: at)
      end

      def file_context(path:, line: nil, before: 3, after: 3, at: 'worktree')
        root = ensure_root!(nil)
        Savant::Git::FileContext.context_for_line(root: root, path: path, line: line, before: before, after: after, at: at)
      end

      private

      def ensure_root!(path)
        root = @detector.root(path: path)
        raise 'not a git repository' unless root

        root
      end

      def parse_status_porcelain(out)
        # Lines like:
        #  M file.txt
        # A  lib/new.rb
        # D  old.txt
        out.lines.map(&:rstrip).reject(&:empty?).map do |line|
          status = line[0, 2].strip
          path = line[3..]&.strip || ''
          { status: status.empty? ? '?' : status, path: path }
        end
      end

      def diff_for_file(root:, path:, staged: false)
        flags = ['-U3']
        flags << '--cached' if staged
        cmd = ['git', '-C', root, 'diff', *flags, '--', path]
        out, err, st = Open3.capture3(*cmd)
        raise err.strip unless st.success?

        out
      end
    end
  end
end
