#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require 'shellwords'
require_relative '../../logging/logger'

module Savant
  module Git
    # Detects repository root and metadata.
    class RepoDetector
      def initialize
        @log = Savant::Logging::Logger.new(io: $stdout, json: true, service: 'git.repo')
      end

      def root(path: nil)
        dir = path && !path.to_s.strip.empty? ? File.expand_path(path) : Dir.pwd
        out, _err, st = Open3.capture3('git', '-C', dir, 'rev-parse', '--show-toplevel')
        return nil unless st.success?

        out.strip
      end

      def status(path: nil)
        r = root(path: path)
        return { is_repo: false, path: path || Dir.pwd } unless r

        branch = capture('git', '-C', r, 'rev-parse', '--abbrev-ref', 'HEAD')&.strip
        head = capture('git', '-C', r, 'rev-parse', 'HEAD')&.strip
        files = capture('git', '-C', r, 'ls-files', '-z')
        tracked = files ? files.split("\x0").reject(&:empty?) : []
        { is_repo: true, path: r, branch: branch, head: head, tracked_files: tracked.size, languages: summarize_languages(tracked) }
      end

      private

      def capture(*cmd)
        out, _err, st = Open3.capture3(*cmd)
        return nil unless st.success?

        out
      end

      def summarize_languages(paths)
        counts = Hash.new(0)
        paths.each do |p|
          ext = File.extname(p).downcase
          key = ext.empty? ? 'other' : ext.delete_prefix('.')
          counts[key] += 1
        end
        counts.sort_by { |_, v| -v }.to_h
      end
    end
  end
end
