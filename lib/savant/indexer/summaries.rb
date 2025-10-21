#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Generate summaries during indexing for persistence to Postgres.
#
# This module belongs to the indexing layer and provides a simple abstraction
# for summarizing text as part of ingestion. It prefers the optional 'summarize'
# gem when available and falls back to a deterministic heuristic.
require 'time'
begin
  require 'summarize'
rescue LoadError
  # optional dependency
end

module Savant
  module Indexer
    module Summaries
      module_function

      # Summarize text for storage. Returns a Hash with metadata:
      # { text: String, length: Integer, source: 'summarize'|'heuristic'|'none', generated_at: ISO8601 String }
      def summarize(text, max_length: 300)
        txt = text.to_s.strip
        return { text: '', length: 0, source: 'none', generated_at: Time.now.utc.iso8601 } if txt.empty?

        if defined?(Summarize)
          begin
            out = Summarize.summarize(txt, max_length: max_length).to_s.strip
            if out.nil? || out.empty?
              out = heuristic(txt, max_length)
              src = 'heuristic'
            else
              src = 'summarize'
            end
            return { text: out, length: out.length, source: src, generated_at: Time.now.utc.iso8601 }
          rescue StandardError => _e
            # fall back
          end
        end
        out = heuristic(txt, max_length)
        { text: out, length: out.length, source: 'heuristic', generated_at: Time.now.utc.iso8601 }
      end

      # Heuristic: take the first paragraph and trim to max length.
      def heuristic(txt, max_length)
        para = txt.split(/\n\n+/).first.to_s.strip
        para.length > max_length ? "#{para[0, max_length - 1]}…" : para
      end
    end
  end
end
