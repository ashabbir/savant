#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../framework/mcp/core/dsl'
require_relative 'engine'

module Savant
  module Council
    module Tools
      module_function

      def build_registrar(engine = nil)
        eng = engine || Savant::Council::Engine.new
        Savant::Framework::MCP::Core::DSL.build do
          # =========================
          # Session Management Tools
          # =========================

          tool 'council_session_create', description: 'Create a Council session',
               schema: { type: 'object', properties: { title: { type: 'string' }, description: { type: 'string' }, agents: { type: 'array', items: { type: 'string' } } } } do |ctx, a|
            user_id = ctx && ctx[:user_id]
            eng.session_create(title: a['title'], description: a['description'], agents: a['agents'] || [], user_id: user_id)
          end

          tool 'council_sessions_list', description: 'List Council sessions',
               schema: { type: 'object', properties: { limit: { type: 'integer' } } } do |_ctx, a|
            { sessions: eng.sessions_list(limit: (a['limit'] || 50)) }
          end

          tool 'council_session_get', description: 'Get a Council session with messages, mode, and council run status',
               schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] } do |_ctx, a|
            eng.session_get(id: a['id'])
          end

          tool 'council_session_update', description: 'Update a Council session metadata (title, description and/or agents)',
               schema: { type: 'object', properties: { id: { type: 'integer' }, title: { type: 'string' }, description: { type: 'string' }, agents: { type: 'array', items: { type: 'string' } } }, required: ['id'] } do |_ctx, a|
            eng.session_update(id: a['id'], title: a['title'], agents: a['agents'], description: a['description'])
          end

          tool 'council_session_delete', description: 'Delete a Council session',
               schema: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] } do |_ctx, a|
            eng.session_delete(id: a['id'])
          end

          # =========================
          # Chat Mode Tools
          # =========================

          tool 'council_append_user', description: 'Append a user message to a session (chat mode)',
               schema: { type: 'object', properties: { session_id: { type: 'integer' }, text: { type: 'string' } }, required: %w[session_id text] } do |ctx, a|
            user_id = ctx && ctx[:user_id]
            eng.append_user(session_id: a['session_id'], text: a['text'], user_id: user_id)
          end

          tool 'council_append_agent', description: 'Append an agent reply to a session',
               schema: { type: 'object', properties: { session_id: { type: 'integer' }, agent_name: { type: 'string' }, run_id: { type: 'integer' }, text: { type: 'string' }, status: { type: 'string' } }, required: %w[session_id agent_name] } do |_ctx, a|
            eng.append_agent(session_id: a['session_id'], agent_name: a['agent_name'], run_id: a['run_id'], text: a['text'], status: a['status'] || 'ok')
          end

          tool 'council_agent_step', description: 'Run one reasoning step for a Council session and append the agent reply',
               schema: {
                 type: 'object',
                 properties: {
                   session_id: { type: 'integer' },
                   goal_text: { type: 'string' },
                   agent_name: { type: 'string' }
                 },
                 required: ['session_id', 'goal_text']
               } do |_ctx, a|
            eng.agent_step(session_id: a['session_id'], goal_text: a['goal_text'], agent_name: a['agent_name'])
          end

          # =========================
          # Council Protocol Tools
          # =========================

          tool 'council_roles', description: 'Get available council roles (Analyst, Skeptic, Pragmatist, Safety/Ethics, Moderator)',
               schema: { type: 'object', properties: {} } do |_ctx, _a|
            { roles: eng.council_roles }
          end

          tool 'council_status', description: 'Get the current status of a council session (mode, current run, roles)',
               schema: { type: 'object', properties: { session_id: { type: 'integer' } }, required: ['session_id'] } do |_ctx, a|
            eng.council_status(session_id: a['session_id'])
          end

          tool 'council_escalate', description: 'Escalate from chat mode to council mode. Freezes conversation context and starts council deliberation.',
               schema: {
                 type: 'object',
                 properties: {
                   session_id: { type: 'integer', description: 'The session to escalate' },
                   query: { type: 'string', description: 'The decision query for the council (optional, extracted from conversation if not provided)' }
                 },
                 required: ['session_id']
               } do |ctx, a|
            user_id = ctx && ctx[:user_id]
            eng.escalate_to_council(session_id: a['session_id'], query: a['query'], user_id: user_id)
          end

          tool 'council_run', description: 'Run the full council protocol (Initial Positions → Debate → Synthesis). Returns the final recommendation.',
               schema: {
                 type: 'object',
                 properties: {
                   session_id: { type: 'integer', description: 'The session to run council for' },
                   run_id: { type: 'string', description: 'Specific council run ID (optional, uses latest if not provided)' },
                   max_debate_rounds: { type: 'integer', description: 'Maximum debate rounds (default: 2)' }
                 },
                 required: ['session_id']
               } do |_ctx, a|
            eng.run_council(
              session_id: a['session_id'],
              run_id: a['run_id'],
              max_debate_rounds: a['max_debate_rounds'] || 2
            )
          end

          tool 'council_return_to_chat', description: 'Return from council mode to chat mode',
               schema: {
                 type: 'object',
                 properties: {
                   session_id: { type: 'integer' },
                   message: { type: 'string', description: 'Optional message to append when returning to chat' }
                 },
                 required: ['session_id']
               } do |_ctx, a|
            eng.return_to_chat(session_id: a['session_id'], message: a['message'])
          end

          tool 'council_run_get', description: 'Get details of a specific council run',
               schema: {
                 type: 'object',
                 properties: {
                   run_id: { type: 'string', description: 'The council run ID' }
                 },
                 required: ['run_id']
               } do |_ctx, a|
            eng.get_council_run(run_id: a['run_id'])
          end

          tool 'council_runs_list', description: 'List all council runs for a session',
               schema: {
                 type: 'object',
                 properties: {
                   session_id: { type: 'integer' },
                   limit: { type: 'integer', description: 'Maximum runs to return (default: 20)' }
                 },
                 required: ['session_id']
               } do |_ctx, a|
            { runs: eng.list_council_runs(session_id: a['session_id'], limit: a['limit'] || 20) }
          end
        end
      end
    end
  end
end
