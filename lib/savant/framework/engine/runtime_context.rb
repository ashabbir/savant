#!/usr/bin/env ruby
# frozen_string_literal: true

module Savant
  # RuntimeContext holds all runtime state for the Savant Engine.
  # Accessible globally as Savant::Framework::Runtime.current
  RuntimeContext = Struct.new(
    :session_id,
    :persona,
    :driver_prompt,
    :amr_rules,
    :agent_rulesets,
    :repo,
    :memory,
    :logger,
    :multiplexer,
    keyword_init: true
  ) do
    def to_h
      {
        session_id: session_id,
        persona: persona,
        driver_prompt: driver_prompt&.dig(:version),
        amr_rules: amr_rules&.dig(:rules) ? "#{amr_rules[:rules].size} rules" : nil,
        agent_rulesets: agent_rulesets.is_a?(Array) ? "#{agent_rulesets.size} rulesets" : nil,
        repo: repo&.dig(:path),
        memory: memory ? 'initialized' : nil
      }
    end
  end

  module Framework
    # Global runtime accessor
    module Runtime
      class << self
        attr_accessor :current
      end
    end
  end
end
