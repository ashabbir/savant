#!/usr/bin/env ruby
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
    class Engine
      DEFAULT_FIELDS = %w[key summary status assignee updated].freeze

      def initialize(env: ENV)
        base_url = fetch(env, 'JIRA_BASE_URL')
        email = env['JIRA_EMAIL']; api_token = env['JIRA_API_TOKEN']
        username = env['JIRA_USERNAME']; password = env['JIRA_PASSWORD']
        @allow_writes = (env['JIRA_ALLOW_WRITES'].to_s.downcase == 'true')
        @client = Client.new(base_url: base_url, email: email, api_token: api_token, username: username, password: password)
        @ops = Ops.new(@client)
      end

      def search(jql:, limit: 10, start_at: 0)
        @ops.search(jql: jql, limit: limit, start_at: start_at, fields: DEFAULT_FIELDS)
      end

      def self_test
        @client.get('/rest/api/3/myself')
      end

      # passthroughs with write guards where needed
      def get_issue(**args) = @ops.get_issue(**args)
      def create_issue(**args) = with_write_guard { @ops.create_issue(**args) }
      def update_issue(**args) = with_write_guard { @ops.update_issue(**args) }
      def transition_issue(**args) = with_write_guard { @ops.transition_issue(**args) }
      def add_comment(**args) = with_write_guard { @ops.add_comment(**args) }
      def delete_comment(**args) = with_write_guard { @ops.delete_comment(**args) }
      def assign_issue(**args) = with_write_guard { @ops.assign_issue(**args) }
      def link_issues(**args) = with_write_guard { @ops.link_issues(**args) }
      def download_attachments(**args) = @ops.download_attachments(**args)
      def add_attachment(**args) = with_write_guard { @ops.add_attachment(**args) }
      def bulk_create_issues(**args) = with_write_guard { @ops.bulk_create_issues(**args) }
      def list_projects = @ops.list_projects
      def list_fields = @ops.list_fields
      def list_transitions(**args) = @ops.list_transitions(**args)
      def list_statuses(**args) = @ops.list_statuses(**args)
      def delete_issue(**args) = with_write_guard { @ops.delete_issue(**args) }

      private

      def fetch(env, k)
        v = env[k]
        raise "#{k} is required" if v.to_s.strip.empty?
        v
      end

      def with_write_guard
        raise 'writes disabled: set JIRA_ALLOW_WRITES=true' unless @allow_writes
        yield
      end
    end
  end
end
