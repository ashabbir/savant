#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'engine'
require_relative '../mcp/core/dsl'
require_relative '../mcp/core/validation'

module Savant
  module Think
    # MCP tools registrar for the Think service.
    module Tools
      module_function

      def specs
        build_registrar.specs
      end

      def dispatch(engine, name, args)
        reg = build_registrar(engine)
        reg.call(name, args || {}, ctx: { engine: engine })
      end

      def build_registrar(engine = nil)
        eng = engine || Savant::Think::Engine.new
        Savant::MCP::Core::DSL.build do
          # Validation middleware
          middleware do |ctx, name, a, nxt|
            schema = ctx[:schema]
            a2 = begin
              Savant::MCP::Core::Validation.validate!(schema, a)
            rescue Savant::MCP::Core::ValidationError => e
              raise "validation error: #{e.message}"
            end
            nxt.call(ctx, name, a2)
          end

          tool 'think.driver_prompt', description: 'Return versioned driver prompt markdown',
                                      schema: { type: 'object', properties: { version: { type: 'string' } } } do |_ctx, a|
            eng.driver_prompt(version: a['version'])
          end

          tool 'think.plan', description: 'Initialize a workflow run and return first instruction',
                             schema: { type: 'object', properties: { workflow: { type: 'string' }, params: { type: 'object' } }, required: ['workflow'] } do |_ctx, a|
            eng.plan(workflow: a['workflow'].to_s, params: a['params'] || {})
          end

          tool 'think.next', description: 'Advance a workflow by recording step result and returning next instruction',
                             schema: { type: 'object', properties: { workflow: { type: 'string' }, step_id: { type: 'string' }, result_snapshot: { type: 'object' } }, required: %w[workflow step_id] } do |_ctx, a|
            eng.next(workflow: a['workflow'].to_s, step_id: a['step_id'].to_s, result_snapshot: a['result_snapshot'] || {})
          end

          tool 'think.workflows.list', description: 'List available workflows',
                                       schema: { type: 'object', properties: { filter: { type: 'string' } } } do |_ctx, a|
            eng.workflows_list(filter: a['filter'])
          end

          tool 'think.workflows.read', description: 'Read raw workflow YAML',
                                       schema: { type: 'object', properties: { workflow: { type: 'string' } }, required: ['workflow'] } do |_ctx, a|
            eng.workflows_read(workflow: a['workflow'])
          end

          # NOTE: Think does not re‑expose Context FTS or local FS search.
          # The Instruction Engine should guide the LLM to call Context MCP tools
          # (e.g., 'fts/search') and perform local workspace searches using its
          # editor capabilities.

          # Check: RuboCop offenses summary (does not modify files)
          tool 'check/rubocop', description: 'Run RuboCop and return offense counts',
                                schema: { type: 'object', properties: { format: { type: 'string' } } } do |_ctx, _a|
            require 'open3'
            cmd = ['bash', '-lc', 'bundle exec rubocop -f json || rubocop -f json']
            out, err, status = Open3.capture3(*cmd)
            if status.exitstatus.nil?
              { ok: false, error: 'rubocop_not_available', stderr: err }
            else
              begin
                data = JSON.parse(out)
                summary = data['summary'] || {}
                offenses = summary['offense_count'] || 0
                files = summary['inspected_file_count'] || 0
                { ok: offenses.to_i.zero?, offenses: offenses, files_inspected: files }
              rescue StandardError
                { ok: status.success?, raw: out[-2000..], stderr: err[-1000..] }
              end
            end
          end

          # Check: RSpec run with coverage threshold (parses SimpleCov/builtin output)
          tool 'check/rspec', description: 'Run RSpec and assert minimum coverage',
                              schema: { type: 'object', properties: { min_coverage: { type: 'integer', minimum: 0, maximum: 100 } } } do |_ctx, a|
            require 'open3'
            min_cov = (a['min_coverage'] || 85).to_i
            out, err, status = Open3.capture3('bash', '-lc', 'rspec --format progress')
            coverage = nil
            # Try SimpleCov line
            if (m = out.match(/Line Coverage:\s*(\d+(?:\.\d+)?)%/))
              coverage = m[1].to_f
            elsif (m = out.match(/Coverage \(builtin\):\s*(\d+(?:\.\d+)?)%/))
              coverage = m[1].to_f
            end
            meets = !coverage.nil? && coverage >= min_cov
            { ok: status.success? && meets, passed: status.success?, coverage: coverage, min_coverage: min_cov, meets_threshold: meets, stderr: err[-500..] }
          end
        end
      end
    end
  end
end
