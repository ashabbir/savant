#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'ollama'
require_relative 'anthropic'
require_relative 'openai'

module Savant
  module LLM
    class ProviderError < StandardError; end

    DEFAULT_SLM = ENV['SLM_MODEL'] || 'phi3.5:latest'
    DEFAULT_LLM = ENV['LLM_MODEL'] || 'llama3:latest'

    # Unified call surface.
    # Params:
    # - prompt [String]
    # - model [String]
    # - system [String,nil]
    # - json [Boolean]
    # - max_tokens [Integer,nil]
    # - temperature [Numeric,nil]
    # - provider [:ollama,:anthropic,:openai,nil]
    # Returns: { text: String, usage: { prompt_tokens:, output_tokens: } }
    def self.call(prompt:, model: nil, system: nil, json: false, max_tokens: nil, temperature: nil, provider: nil)
      use_model = model && !model.to_s.empty? ? model.to_s : DEFAULT_SLM
      prov = (provider || default_provider_for(use_model)).to_sym
      case prov
      when :ollama
        Savant::LLM::Ollama.generate(
          prompt: prompt,
          model: use_model,
          system: system,
          json: json,
          max_tokens: max_tokens,
          temperature: temperature
        )
      when :anthropic
        Savant::LLM::Anthropic.generate(
          prompt: prompt,
          model: use_model,
          system: system,
          json: json,
          max_tokens: max_tokens,
          temperature: temperature
        )
      when :openai
        Savant::LLM::OpenAI.generate(
          prompt: prompt,
          model: use_model,
          system: system,
          json: json,
          max_tokens: max_tokens,
          temperature: temperature
        )
      else
        raise ProviderError, "unknown provider: #{prov}"
      end
    end

    def self.default_provider_for(model)
      # Simple heuristic: use ollama by default; allow explicit prefixes
      return :openai if model.to_s.start_with?('gpt-')
      return :anthropic if model.to_s.start_with?('claude')

      :ollama
    end
  end
end
