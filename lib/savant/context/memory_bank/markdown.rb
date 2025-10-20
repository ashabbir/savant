#!/usr/bin/env ruby
#
# Purpose: Markdown helpers for memory_bank content.
#
# Provides minimal utilities to strip front‑matter, convert markdown to plain
# text, and extract the first heading as a title. These helpers intentionally
# avoid heavy dependencies and aim for predictable text suitable for search and
# snippet generation.
require 'time'

module Savant
  module Context
    module MemoryBank
      module Markdown
        module_function

        def strip_frontmatter(text)
          return text unless text.start_with?("---\n")
          parts = text.split(/^---\s*$\n/, 3)
          return text if parts.length < 3
          parts[2]
        end

        def markdown_to_text(md)
          md = md.to_s.dup
          md = strip_frontmatter(md)
          # Remove code fences
          md.gsub!(/```[\s\S]*?```/m, '')
          # Remove inline code
          md.gsub!(/`[^`]*`/, '')
          # Replace images/links with their text
          md.gsub!(/!\[[^\]]*\]\([^\)]*\)/, '')
          md.gsub!(/\[([^\]]+)\]\([^\)]*\)/, '\\1')
          # Strip HTML tags
          md.gsub!(/<[^>]+>/, '')
          # Normalize headings/bold/italics markers
          md.gsub!(/^#+\s*/, '')
          md.gsub!(/[\*_]{1,3}([^\*_]+)[\*_]{1,3}/, '\\1')
          # Collapse whitespace
          md.gsub!(/\r\n?/, "\n")
          md = md.lines.map(&:rstrip).join("\n")
          md.gsub!(/\n{3,}/, "\n\n")
          md.strip
        end

        def extract_title(md, fallback_name)
          if (m = md.match(/^#\s+(.+)$/))
            title = m[1].to_s
          else
            title = File.basename(fallback_name).sub(/\.[^.]+$/, '')
          end
          title = title.strip.gsub(/\s+/, ' ')
          title[0, 120]
        end
      end
    end
  end
end
