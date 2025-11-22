#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Orchestrate Jira MCP tools and guard writes.
#
# Wires a Jira::Client to Jira::Ops and exposes high-level methods for MCP
# tools. Enforces write permissions via JIRA_ALLOW_WRITES and centralizes
# default fields and environment lookups.

require_relative 'client'
require_relative 'ops'
require 'json'

module Savant
  module Jira
    # Orchestrates Jira tools and delegates to Ops/Client.
    #
    # Purpose: Provide a façade for MCP Jira service, wiring auth/client and
    # exposing high-level methods invoked by the registrar.
    # Jira Engine façade that wires Client and Ops.
    #
    # Purpose: Centralize auth/env, expose a safe public API for tools, and
    # gate write operations behind an explicit allow flag.
    class Engine
      DEFAULT_FIELDS = %w[key summary status assignee updated].freeze

      # @param env [#[]] environment-like hash for credentials and flags.
      def initialize(env: ENV)
        # Try loading default credentials from SecretStore first, then fall back to ENV
        creds = load_default_credentials
        base_url = creds[:base_url] || env['JIRA_BASE_URL']
        raise 'JIRA_BASE_URL is required (set via secrets.yml default user or env var)' if base_url.to_s.strip.empty?

        email = creds[:email] || env['JIRA_EMAIL']
        api_token = creds[:api_token] || env['JIRA_API_TOKEN']
        username = creds[:username] || env['JIRA_USERNAME']
        password = creds[:password] || env['JIRA_PASSWORD']
        @allow_writes = creds[:allow_writes] || (env['JIRA_ALLOW_WRITES'].to_s.downcase == 'true')
        @client = Client.new(
          base_url: base_url,
          email: email,
          api_token: api_token,
          username: username,
          password: password
        )
        @ops = Ops.new(@client)
        @mutex = Mutex.new
      end

      # Run a JQL search with sane defaults.
      # @param jql [String]
      # @param limit [Integer]
      # @param start_at [Integer]
      # @return [Hash] Jira search results
      def search(jql:, limit: 10, start_at: 0)
        @ops.search(jql: jql, limit: limit, start_at: start_at, fields: DEFAULT_FIELDS)
      end

      # Verify credentials by calling the `myself` endpoint.
      # @return [Hash] user info
      def self_test
        @client.get('/rest/api/3/myself')
      end

      # passthroughs with write guards where needed
      # @return [Hash]
      def get_issue(**args)
        @ops.get_issue(**args)
      end

      # @return [Hash]
      def create_issue(**args)
        with_write_guard { @ops.create_issue(**args) }
      end

      # @return [Hash]
      def update_issue(**args)
        with_write_guard { @ops.update_issue(**args) }
      end

      # @return [Hash]
      def transition_issue(**args)
        with_write_guard { @ops.transition_issue(**args) }
      end

      # @return [Hash]
      def add_comment(**args)
        with_write_guard { @ops.add_comment(**args) }
      end

      # @return [Hash]
      def delete_comment(**args)
        with_write_guard { @ops.delete_comment(**args) }
      end

      # @return [Hash]
      def assign_issue(**args)
        with_write_guard { @ops.assign_issue(**args) }
      end

      # @return [Hash]
      def link_issues(**args)
        with_write_guard { @ops.link_issues(**args) }
      end

      # @return [Array<Hash>]
      def download_attachments(**args)
        @ops.download_attachments(**args)
      end

      # @return [Hash]
      def add_attachment(**args)
        with_write_guard { @ops.add_attachment(**args) }
      end

      # @return [Hash]
      def bulk_create_issues(**args)
        with_write_guard { @ops.bulk_create_issues(**args) }
      end

      # @return [Array<Hash>]
      def list_projects
        @ops.list_projects
      end

      # @return [Array<Hash>]
      def list_fields
        @ops.list_fields
      end

      # @return [Array<Hash>]
      def list_transitions(**args)
        @ops.list_transitions(**args)
      end

      # @return [Array<Hash>]
      def list_statuses(**args)
        @ops.list_statuses(**args)
      end

      # @return [Hash]
      def delete_issue(**args)
        with_write_guard { @ops.delete_issue(**args) }
      end

      private

      # Load default credentials from SecretStore using 'default' or '_system_' user.
      # @return [Hash] credential hash with symbolized keys (base_url, email, api_token, etc.)
      def load_default_credentials
        require_relative '../secret_store'
        # Try 'default' user first, then '_system_', to get default Jira credentials
        %w[default _system_].each do |user_id|
          creds = Savant::SecretStore.for(user_id, :jira)
          next unless creds && !creds.empty?

          # Normalize keys (support both base_url and jira_base_url patterns)
          return {
            base_url: creds[:base_url] || creds['base_url'] || creds[:jira_base_url] || creds['jira_base_url'],
            email: creds[:email] || creds['email'] || creds[:jira_email] || creds['jira_email'],
            api_token: creds[:api_token] || creds['api_token'] || creds[:jira_token] || creds['jira_token'],
            username: creds[:username] || creds['username'],
            password: creds[:password] || creds['password'],
            allow_writes: %w[true 1 yes].include?((creds[:allow_writes] || creds['allow_writes']).to_s.downcase)
          }
        end
        {}
      rescue StandardError
        {}
      end

      # Fetch and require a non-empty env var value.
      # @param env [#[]]
      # @param key [String]
      # @return [String]
      # @raise [RuntimeError] when missing/empty
      def fetch(env, key)
        v = env[key]
        raise "#{key} is required" if v.to_s.strip.empty?

        v
      end

      # Ensure writes are enabled before yielding.
      # @raise [RuntimeError] when writes are disabled
      def with_write_guard
        raise 'writes disabled: set JIRA_ALLOW_WRITES=true' unless @allow_writes

        yield
      end

      public

      # Temporarily apply per-user credentials for the duration of the block.
      # Looks up from SecretStore using provided user_id and expected keys.
      # Supported keys under service :jira: base_url, email+api_token OR username+password.
      def with_user_credentials(user_id)
        require_relative '../secret_store'
        creds = Savant::SecretStore.for(user_id, :jira)
        return yield unless creds

        # From secrets file with ENV fallbacks so partial config works
        base_url = creds[:base_url] || creds['base_url'] || creds[:jira_base_url] || creds['jira_base_url'] || ENV['JIRA_BASE_URL']
        email = creds[:email] || creds['email'] || creds[:jira_email] || creds['jira_email'] || ENV['JIRA_EMAIL']
        api_token = creds[:api_token] || creds['api_token'] || creds[:jira_token] || creds['jira_token'] || ENV['JIRA_API_TOKEN']
        username = creds[:username] || creds['username'] || ENV['JIRA_USERNAME']
        password = creds[:password] || creds['password'] || ENV['JIRA_PASSWORD']

        # Require at least base_url and one auth method
        return yield if base_url.to_s.strip.empty?
        return yield if (email.to_s.strip.empty? || api_token.to_s.strip.empty?) && (username.to_s.strip.empty? || password.to_s.strip.empty?)

        old_client = @client
        old_ops = @ops
        @mutex.synchronize do
          begin
            @client = Client.new(base_url: base_url, email: email, api_token: api_token, username: username, password: password)
            @ops = Ops.new(@client)
            return yield
          ensure
            @client = old_client
            @ops = old_ops
          end
        end
      end

      # Server info metadata surfaced to MCP server during initialize
      # Returns: { name:, version:, description: }
      # Server info metadata surfaced to MCP server during initialize.
      # @return [Hash] { name:, version:, description: }
      def server_info
        {
          name: 'savant-jira',
          version: '1.1.0',
          description: 'Jira MCP: jira_* tools (search, issue ops, comments, attachments)'
        }
      end
    end
  end
end
