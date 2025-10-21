#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Load and validate application configuration.
#
# `Savant::Config.load(path)` reads `config/settings.json`, validates required
# structure and keys, and raises `Savant::ConfigError` for any invalid input.
# This module enforces presence of top-level sections (indexer, database, mcp)
# and sanity-checks repo entries and indexer fields.

require 'json'

module Savant
  # Error raised when configuration is missing or invalid.
  #
  # Purpose: Distinguish config validation/load failures from other runtime
  # errors so callers can present actionable messages.
  class ConfigError < StandardError; end

  # Loads and validates application settings from `settings.json`.
  #
  # Purpose: Provide a single entrypoint for config IO and validation used by
  # the indexer and MCP services. Ensures presence and shape of required keys
  # and raises {Savant::ConfigError} on problems.
  #
  # @example Load validated settings
  #   cfg = Savant::Config.load('config/settings.json')
  #   cfg['indexer']['repos'].each { |r| puts r['name'] }
  class Config
    # Load and validate JSON settings.
    #
    # @param path [String] absolute or relative path to `settings.json`.
    # @return [Hash] parsed and validated settings hash.
    # @raise [Savant::ConfigError] when the file is missing or invalid.
    def self.load(path)
      raise ConfigError, 'SETTINGS_PATH not provided' if path.nil? || path.strip.empty?
      raise ConfigError, "missing settings.json at #{path}" unless File.exist?(path)

      begin
        data = JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise ConfigError, "invalid JSON: #{e.message}"
      end

      validate!(data)
      data
    end

    # Validate the parsed settings hash in-place.
    #
    # Purpose: Enforce required structure and provide early, precise errors.
    # @param cfg [Hash] parsed settings.
    # @return [true] when valid.
    # @raise [Savant::ConfigError] on missing keys or bad types.
    def self.validate!(cfg)
      # Validate new layout: indexer + repos + mcp + database at root
      req = {
        'indexer' => %w[maxFileSizeKB languages chunk repos],
        'mcp' => nil,
        'database' => %w[host port db user password]
      }

      req.each do |key, inner|
        raise ConfigError, "missing key: #{key}" unless cfg.key?(key)

        next unless inner

        inner.each do |sub|
          raise ConfigError, "missing key: #{key}.#{sub}" unless cfg[key].is_a?(Hash) && cfg[key].key?(sub)
        end
      end

      unless cfg.dig('indexer', 'repos').is_a?(Array) && cfg['indexer']['repos'].any?
        raise ConfigError, 'repos must be a non-empty array'
      end

      cfg['indexer']['repos'].each do |r|
        raise ConfigError, 'repo missing name' unless r['name'].is_a?(String) && !r['name'].empty?
        raise ConfigError, "repo #{r['name']} missing path" unless r['path'].is_a?(String) && !r['path'].empty?
        raise ConfigError, "repo #{r['name']} ignore must be array" if r['ignore'] && !r['ignore'].is_a?(Array)
      end
      true
    end
  end
end
