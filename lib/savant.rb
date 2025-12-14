# frozen_string_literal: true

# Savant main entry point - loads all necessary modules
require_relative 'savant/version'
require_relative 'savant/framework/db'
require_relative 'savant/logging/mongo_logger'
require_relative 'savant/engines/llm/vault'
require_relative 'savant/engines/llm/registry'
require_relative 'savant/engines/llm/adapters'
require_relative 'savant/engines/llm/engine'

module Savant
  # Main module for Savant
end
