#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: MCP registrar/dispatcher for Jira tools (DSL-based).

require 'json'
require_relative 'engine'
require_relative '../mcp/core/dsl'

module Savant
  module Jira
    module Tools
      module_function

      # Return the MCP tool specs for the Jira service.
      # @return [Array<Hash>] tool definitions
      def specs
        build_registrar.specs
      end

      # Dispatch a tool call by name to the Jira engine.
      # @param engine [Savant::Jira::Engine]
      # @param name [String]
      # @param args [Hash]
      # @return [Object] tool-specific result
      def dispatch(engine, name, args)
        reg = build_registrar(engine)
        reg.call(name, args || {}, ctx: { engine: engine })
      end

      # Build the registrar containing all Jira tools.
      # @param engine [Savant::Jira::Engine, nil]
      # @return [Savant::MCP::Core::Registrar]
      def build_registrar(engine = nil)
        Savant::MCP::Core::DSL.build do
          # Structured logging middleware (framework default)
          middleware do |ctx, nm, a, nxt|
            logger = ctx[:logger] || Savant::Logger.new(io: $stdout, json: true, service: 'jira')
            start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            begin
              logger.trace(event: 'tool_start', tool: nm, request_id: ctx[:request_id])
              out = nxt.call(ctx, nm, a)
              dur_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
              logger.trace(event: 'tool_end', tool: nm, duration_ms: dur_ms, status: 'ok', request_id: ctx[:request_id])
              out
            rescue StandardError => e
              dur_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
              logger.error(event: 'exception', tool: nm, duration_ms: dur_ms, message: e.message, request_id: ctx[:request_id])
              raise
            end
          end
          require_relative '../mcp/core/validation'
          # Validation middleware
          middleware do |ctx, nm, a, nxt|
            schema = ctx[:schema]
            a2 = begin
              Savant::MCP::Core::Validation.validate!(schema, a)
            rescue Savant::MCP::Core::ValidationError => e
              raise "validation error: #{e.message}"
            end
            nxt.call(ctx, nm, a2)
          end

          # Minimal logging
          middleware do |ctx, nm, a, nxt|
            start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            out = nxt.call(ctx, nm, a)
            dur_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
            begin
              engine.instance_variable_get(:@log).info("tool: name=#{nm} dur_ms=#{dur_ms}")
            rescue StandardError
            end
            out
          end

          # Tools
          tool 'jira_search', description: 'Run a Jira JQL search',
                              schema: { type: 'object', properties: { jql: { type: 'string' }, limit: { type: 'integer', minimum: 1, maximum: 100 }, start_at: { type: 'integer', minimum: 0 } }, required: ['jql'] } do |_ctx, a|
            engine.search(jql: a['jql'].to_s, limit: a['limit'] || 10, start_at: a['start_at'] || 0)
          end

          tool 'jira_get_issue', description: 'Get a Jira issue (v3)',
                                 schema: { type: 'object', properties: { key: { type: 'string' }, fields: { type: 'array', items: { type: 'string' } } }, required: ['key'] } do |_ctx, a|
            engine.get_issue(key: a['key'].to_s, fields: a['fields'])
          end

          tool 'jira_create_issue', description: 'Create a Jira issue (v3)',
                                    schema: { type: 'object', properties: { projectKey: { type: 'string' }, summary: { type: 'string' }, issuetype: { type: 'string' }, description: { type: 'string' }, fields: { type: 'object' } }, required: %w[projectKey summary issuetype] } do |_ctx, a|
            engine.create_issue(projectKey: a['projectKey'], summary: a['summary'], issuetype: a['issuetype'],
                                description: a['description'], fields: a['fields'] || {})
          end

          tool 'jira_update_issue', description: 'Update a Jira issue (v3)',
                                    schema: { type: 'object', properties: { key: { type: 'string' }, fields: { type: 'object' } }, required: %w[key fields] } do |_ctx, a|
            engine.update_issue(key: a['key'], fields: a['fields'] || {})
          end

          tool 'jira_transition_issue', description: 'Transition a Jira issue (v3)',
                                        schema: { type: 'object', properties: { key: { type: 'string' }, transitionName: { type: 'string' }, transitionId: { type: 'string' } }, required: ['key'] } do |_ctx, a|
            engine.transition_issue(key: a['key'], transitionName: a['transitionName'], transitionId: a['transitionId'])
          end

          tool 'jira_add_comment', description: 'Add a comment to an issue (v3)',
                                   schema: { type: 'object', properties: { key: { type: 'string' }, body: { type: 'string' } }, required: %w[key body] } do |_ctx, a|
            engine.add_comment(key: a['key'], body: a['body'])
          end

          tool 'jira_delete_comment', description: 'Delete a comment (v3)',
                                      schema: { type: 'object', properties: { key: { type: 'string' }, id: { type: 'string' } }, required: %w[key id] } do |_ctx, a|
            engine.delete_comment(key: a['key'], id: a['id'])
          end

          tool 'jira_download_attachments', description: 'Download issue attachments (v3)',
                                            schema: { type: 'object', properties: { key: { type: 'string' } }, required: ['key'] } do |_ctx, a|
            engine.download_attachments(key: a['key'])
          end

          tool 'jira_add_attachment', description: 'Upload attachment to issue (v3)',
                                      schema: { type: 'object', properties: { key: { type: 'string' }, filePath: { type: 'string' } }, required: %w[key filePath] } do |_ctx, a|
            engine.add_attachment(key: a['key'], filePath: a['filePath'])
          end

          tool 'jira_add_watcher_to_issue', description: 'Add watcher (v3)',
                                            schema: { type: 'object', properties: { key: { type: 'string' }, accountId: { type: 'string' } }, required: %w[key accountId] } do |_ctx, a|
            client = engine.instance_variable_get(:@client)
            client.post("/rest/api/3/issue/#{a['key']}/watchers", a['accountId'].to_json)
            { added: true }
          end

          tool 'jira_assign_issue', description: 'Assign issue (v3)',
                                    schema: { type: 'object', properties: { key: { type: 'string' }, accountId: { type: 'string' }, name: { type: 'string' } }, required: ['key'] } do |_ctx, a|
            engine.assign_issue(key: a['key'], accountId: a['accountId'], name: a['name'])
          end

          tool 'jira_bulk_create_issues', description: 'Bulk create issues (v3)',
                                          schema: { type: 'object', properties: { issues: { type: 'array', items: { type: 'object' } } }, required: ['issues'] } do |_ctx, a|
            engine.bulk_create_issues(issues: a['issues'] || [])
          end

          tool 'jira_delete_issue', description: 'Delete issue (v3)',
                                    schema: { type: 'object', properties: { key: { type: 'string' } }, required: ['key'] } do |_ctx, a|
            engine.delete_issue(key: a['key'])
          end

          tool 'jira_link_issues', description: 'Link two issues (v3)',
                                   schema: { type: 'object', properties: { inwardKey: { type: 'string' }, outwardKey: { type: 'string' }, linkType: { type: 'string' } }, required: %w[inwardKey outwardKey linkType] } do |_ctx, a|
            engine.link_issues(inwardKey: a['inwardKey'], outwardKey: a['outwardKey'], linkType: a['linkType'])
          end

          tool 'jira_self', description: 'Verify Jira credentials',
                            schema: { type: 'object', properties: {} } do |_ctx, _a|
            engine.self_test
          end
        end
      end
    end
  end
end
