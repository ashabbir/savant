#!/usr/bin/env ruby
# frozen_string_literal: true

module Savant
  module Git
    # Computes added/removed line numbers from a parsed hunk.
    class HunkParser
      def extract(hunk)
        old_line = hunk[:old_start].to_i
        new_line = hunk[:new_start].to_i
        added = []
        removed = []
        (hunk[:lines] || []).each do |ln|
          case ln[:type]
          when 'add'
            added << new_line
            new_line += 1
          when 'del'
            removed << old_line
            old_line += 1
          else
            old_line += 1
            new_line += 1
          end
        end
        {
          old_start: hunk[:old_start], old_lines: hunk[:old_lines],
          new_start: hunk[:new_start], new_lines: hunk[:new_lines],
          added_lines: added, removed_lines: removed
        }
      end
    end
  end
end
