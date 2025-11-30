#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'

module Savant
  module Git
    # File readers and simple line-based contexts.
    class FileContext
      class << self
        def read_file(root:, path:, at: 'worktree')
          if at.to_s.upcase == 'HEAD'
            cmd = ['git', '-C', root, 'show', "HEAD:#{path}"]
            out, err, st = Open3.capture3(*cmd)
            raise err.strip unless st.success?
            out
          else
            fp = File.join(root, path)
            raise 'file not found' unless File.file?(fp)
            File.read(fp)
          end
        end

        def context_for_line(root:, path:, line:, before: 3, after: 3, at: 'worktree')
          line_i = (line || 1).to_i
          text = read_file(root: root, path: path, at: at)
          rows = text.split("\n", -1)
          idx = [[line_i - 1, 0].max, rows.length - 1].min
          start = [idx - before.to_i, 0].min + (idx - before.to_i).abs - (idx - before.to_i).abs # meh: ensure non-negative
          start = [idx - before.to_i, 0].max
          end_i = [idx + after.to_i, rows.length - 1].min
          {
            path: path,
            at: at,
            start_line: start + 1,
            before: rows[start...idx],
            line: rows[idx] || '',
            after: rows[(idx + 1)..end_i] || [],
            total_lines: rows.length
          }
        end
      end
    end
  end
end

