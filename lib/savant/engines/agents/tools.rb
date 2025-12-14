#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../framework/mcp/core/dsl'
require_relative 'engine'

module Savant
  module Agents
    # Tools registrar for agents
    module Tools
      module_function

      def supports_kw?(obj, method_name, kw)
        m = obj.method(method_name)
        m.parameters.any? { |(t, n)| %i[key keyreq].include?(t) && n == kw.to_sym }
      rescue StandardError
        false
      end

      def build_registrar(engine = nil)
        eng = engine || Savant::Agents::Engine.new
        Savant::Framework::MCP::Core::DSL.build do
          tool 'agents_list', description: 'List agents', schema: { type: 'object', properties: {} } do |_ctx, _a|
            { agents: eng.list }
          end

          tool 'agents_get', description: 'Get an agent by name', schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            eng.get(name: a['name'])
          end

          tool 'agents_create', description: 'Create an agent',
                                schema: { type: 'object', properties: {
                                  name: { type: 'string' },
                                  persona: { type: 'string' },
                                  driver: { type: 'string' },
                                  rules: { type: 'array', items: { type: 'string' } },
                                  favorite: { type: 'boolean' },
                                  instructions: { type: 'string' }
                                }, required: %w[name persona driver] } do |_ctx, a|
            eng.create(name: a['name'], persona: a['persona'], driver: a['driver'], rules: a['rules'] || [], favorite: a['favorite'] || false, instructions: a['instructions'])
          end

          tool 'agents_update', description: 'Update an agent (partial)',
                                schema: { type: 'object', properties: {
                                  name: { type: 'string' },
                                  persona: { type: 'string' },
                                  driver: { type: 'string' },
                                  rules: { type: 'array', items: { type: 'string' } },
                                  favorite: { type: 'boolean' },
                                  instructions: { type: 'string' },
                                  model_id: { type: 'integer' }
                                }, required: ['name'] } do |_ctx, a|
            logger = (_ctx && _ctx[:logger]) || begin
              require_relative '../../logging/logger'
              Savant::Logging::MongoLogger.new(service: 'agents')
            rescue StandardError
              nil
            end
            # Coerce favorite properly if present (handle string values from some clients)
            favorite_param = if a.key?('favorite')
              val = a['favorite']
              if val.is_a?(TrueClass) || val.is_a?(FalseClass)
                val
              else
                %w[true 1 t yes y].include?(val.to_s.strip.downcase)
              end
            else
              nil
            end
            logger&.info(event: 'agents_update start', name: a['name'], persona: a['persona'], driver: a['driver'], rules: a['rules'], favorite_raw: a['favorite'], favorite: favorite_param)
            res = eng.update(name: a['name'], persona: a['persona'], driver: a['driver'], rules: a['rules'], favorite: favorite_param, instructions: a['instructions'], model_id: a['model_id'])
            logger&.info(event: 'agents_update finish', name: a['name'], favorite: res[:favorite]) rescue nil
            res
          end

          tool 'agents_delete', description: 'Delete an agent', schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            { ok: eng.delete(name: a['name']) }
          end

          tool 'agents_run', description: 'Execute an agent by name',
                             schema: { type: 'object', properties: {
                               name: { type: 'string' },
                               input: { type: 'string' },
                               max_steps: { type: 'integer' },
                               dry_run: { type: 'boolean' }
                             }, required: %w[name input] } do |_ctx, a|
            user_id = _ctx && _ctx[:user_id]
            if Savant::Agents::Tools.supports_kw?(eng, :run, :user_id)
              eng.run(name: a['name'], input: a['input'], max_steps: a['max_steps'], dry_run: !a['dry_run'].nil?, user_id: user_id)
            else
              eng.run(name: a['name'], input: a['input'], max_steps: a['max_steps'], dry_run: !a['dry_run'].nil?)
            end
          end

          tool 'agents_runs_list', description: 'List recent runs for an agent', schema: { type: 'object', properties: { name: { type: 'string' }, limit: { type: 'integer' } }, required: ['name'] } do |_ctx, a|
            { runs: eng.runs_list(name: a['name'], limit: a['limit'] || 50) }
          end

          tool 'agents_run_read', description: 'Read a single run transcript', schema: { type: 'object', properties: { name: { type: 'string' }, run_id: { type: 'integer' } }, required: %w[name run_id] } do |_ctx, a|
            eng.run_read(name: a['name'], run_id: a['run_id'])
          end

          tool 'agents_run_delete', description: 'Delete a single agent run', schema: { type: 'object', properties: { name: { type: 'string' }, run_id: { type: 'integer' } }, required: %w[name run_id] } do |_ctx, a|
            { ok: eng.run_delete(name: a['name'], run_id: a['run_id']) }
          end

          tool 'agents_runs_clear_all', description: 'Delete all runs for an agent', schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            eng.runs_clear_all(name: a['name'])
          end

          tool 'agents_run_cancel', description: 'Request cancellation for any running agent execution (best effort)',
                                    schema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } do |_ctx, a|
            user_id = _ctx && _ctx[:user_id]
            if Savant::Agents::Tools.supports_kw?(eng, :run_cancel, :user_id)
              eng.run_cancel(name: a['name'], user_id: user_id)
            else
              eng.run_cancel(name: a['name'])
            end
          end
        end
      end
    end
  end
end
