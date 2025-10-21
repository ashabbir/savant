#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Generate simple text snippets around query matches.
#
# The snippet generator locates occurrences of a query string within a larger
# text and returns up to N windows of surrounding context. It is language‑agnostic
# and optimized for speed and determinism, not linguistic accuracy.
module Savant
  module Context
    module MemoryBank
      module Snippets
        module_function

        def make_snippets(text, query, window: 160, max_windows: 2)
          t = text.to_s
          q = query.to_s.strip
          return [] if t.empty? || q.empty?

          lc_t = t.downcase
          lc_q = q.downcase
          idxs = []
          start = 0
          while (pos = lc_t.index(lc_q, start))
            idxs << pos
            break if idxs.length >= (max_windows * 2)

            start = pos + lc_q.length
          end
          return [] if idxs.empty?

          windows = []
          idxs.each do |pos|
            s = [0, pos - window / 2].max
            e = [t.length, s + window].min
            windows << [s, e]
          end
          # de-duplicate overlapping
          merged = []
          windows.sort.each do |w|
            if merged.empty? || w[0] > merged[-1][1]
              merged << w.dup
            else
              merged[-1][1] = [merged[-1][1], w[1]].max
            end
          end
          merged[0, max_windows].map { |s, e| t[s...e] }
        end
      end
    end
  end
end
