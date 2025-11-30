#!/usr/bin/env ruby
# frozen_string_literal: true

module Savant
  module LLM
    module OpenAI
      class << self
        def generate(prompt:, model:, system: nil, json: false, max_tokens: nil, temperature: nil)
          raise StandardError, 'OpenAI backend not configured for MVP (local-first). Set provider to ollama or configure keys.'
        end
      end
    end
  end
end
