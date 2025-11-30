#!/usr/bin/env ruby
# frozen_string_literal: true

module Savant
  module Git
    # Parses unified diff text for a single file into hunks and lines.
    class DiffParser
      HUNK_HEADER = /@@\s*-(\d+)(?:,(\d+))?\s*\+(\d+)(?:,(\d+))?\s*@@(.*)$/

      def parse_file_diff(text)
        hunks = []
        current = nil
        text.to_s.each_line do |line|
          if (m = HUNK_HEADER.match(line))
            current = {
              old_start: m[1].to_i,
              old_lines: (m[2] || '1').to_i,
              new_start: m[3].to_i,
              new_lines: (m[4] || '1').to_i,
              header: line.strip,
              lines: []
            }
            hunks << current
          elsif current
            type = case line[0]
                   when '+' then 'add'
                   when '-' then 'del'
                   else 'context'
                   end
            current[:lines] << { type: type, text: line.sub(/
\z/, '') }
          end
        end
        { hunks: hunks }
      end
    end
  end
end
