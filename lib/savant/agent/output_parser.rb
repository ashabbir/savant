#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

module Savant
  module Agent
    # Parses model output into the strict action envelope.
    class OutputParser
      ACTIONS = %w[tool reason finish error].freeze

      def self.parse(text)
        json = extract_json(text)
        data = JSON.parse(json)
        normalize(data)
      rescue JSON::ParserError
        raise StandardError, 'malformed_json'
      end

      def self.extract_json(text)
        s = text.to_s.strip
        # Prefer fenced JSON
        return Regexp.last_match(1) if s =~ /```json\s*([\s\S]*?)```/i

        # Find first JSON object
        idx = s.index('{')
        raise JSON::ParserError, 'no JSON found' unless idx

        # naive balance braces search
        depth = 0
        (idx...s.length).each do |i|
          ch = s[i]
          depth += 1 if ch == '{'
          depth -= 1 if ch == '}'
          return s[idx..i] if depth.zero?
        end
        raise JSON::ParserError, 'unterminated JSON object'
      end

      def self.normalize(data)
        action_raw = data['action'] || data[:action]
        tool_name_raw = data['tool_name'] || data[:tool_name] || data['tool'] || data[:tool]

        out = {
          'action' => action_raw.to_s,
          'tool_name' => tool_name_raw.to_s,
          'args' => data['args'] || data[:args] || {},
          'final' => data['final'] || data[:final] || '',
          'reasoning' => data['reasoning'] || data[:reasoning] || ''
        }

        # Recovery: If action is not valid but looks like a tool name (contains dot or underscore),
        # and we don't have a tool_name yet, move action to tool_name
        if !ACTIONS.include?(out['action']) && (out['action'].include?('.') || out['action'].include?('_'))
          if out['tool_name'].empty?
            out['tool_name'] = out['action']
            out['action'] = 'tool'
          end
        end

        # If action is invalid but tool_name is set, assume it's a tool call
        if !ACTIONS.include?(out['action']) && !out['tool_name'].empty?
          out['action'] = 'tool'
        end

        # If action is still invalid, mark as error
        unless ACTIONS.include?(out['action'])
          out['action'] = 'error'
          out['final'] = 'Invalid action; expected one of tool|reason|finish|error'
        end

        out['args'] = {} unless out['args'].is_a?(Hash)
        out
      end
    end
  end
end
