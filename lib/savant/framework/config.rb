#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Load and validate application configuration.
#
# `Savant::Framework::Config.load(path)` reads `config/settings.json`, validates required
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

  module Framework
    # Loads and validates application settings from `settings.json`.
    #
    # Purpose: Provide a single entrypoint for config IO and validation used by
    # the indexer and MCP services. Ensures presence and shape of required keys
    # and raises {Savant::ConfigError} on problems.
    #
    # @example Load validated settings
    #   cfg = Savant::Framework::Config.load('config/settings.json')
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
        validate_root!(cfg)
        validate_repos_array!(cfg)
        validate_each_repo!(cfg)
        validate_transport!(cfg)
        true
      end

      def self.validate_root!(cfg)
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
      end

      def self.validate_repos_array!(cfg)
        raise ConfigError, 'repos must be a non-empty array' unless cfg.dig('indexer',
                                                                            'repos').is_a?(Array) && cfg['indexer']['repos'].any?
      end

      def self.validate_each_repo!(cfg)
        cfg['indexer']['repos'].each do |r|
          raise ConfigError, 'repo missing name' unless r['name'].is_a?(String) && !r['name'].empty?
          raise ConfigError, "repo #{r['name']} missing path" unless r['path'].is_a?(String) && !r['path'].empty?
          raise ConfigError, "repo #{r['name']} ignore must be array" if r['ignore'] && !r['ignore'].is_a?(Array)
        end
      end

      def self.validate_transport!(cfg)
        return unless cfg.key?('transport')

        tr = cfg['transport']
        raise ConfigError, 'transport must be an object' unless tr.is_a?(Hash)

        if tr.key?('mode')
          mode = tr['mode']
          raise ConfigError, 'transport.mode must be stdio or websocket' unless %w[stdio websocket].include?(mode)
        end
        return unless tr.key?('websocket')

        ws = tr['websocket']
        raise ConfigError, 'transport.websocket must be an object' unless ws.is_a?(Hash)

        if ws.key?('port') && !(ws['port'].is_a?(Integer) || ws['port'].to_s =~ /^\d+$/)
          raise ConfigError,
                'transport.websocket.port must be integer'
        end
        raise ConfigError, 'transport.websocket.path must be string' if ws.key?('path') && !ws['path'].is_a?(String)
      end
    end
  end
end
