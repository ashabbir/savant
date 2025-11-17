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

          # Bridge: Context FTS search from Think service
          tool 'context.search', description: 'Proxy: Full‑text search over indexed repos (Context FTS)',
                                 schema: { type: 'object', properties: { q: { type: 'string' }, repo: { anyOf: [{ type: 'string' }, { type: 'array', items: { type: 'string' } }, { type: 'null' }] }, limit: { type: 'integer', minimum: 1, maximum: 200 } }, required: ['q'] } do |_ctx, a|
            require_relative '../..//savant/context/fts'
            require_relative '../..//savant/db'
            db = Savant::DB.new
            Savant::Context::FTS.new(db).search(q: (a['q'] || '').to_s, repo: a['repo'], limit: a['limit'] || 20)
          end

          # Filesystem grep in current codebase (verification alongside FTS)
          tool 'fs/grep', description: 'Search current codebase files for a pattern (regex or plain)',
                          schema: { type: 'object', properties: { q: { type: 'string' }, path: { type: 'string' }, globs: { type: 'array', items: { type: 'string' } }, ignore: { type: 'array', items: { type: 'string' } }, limit: { type: 'integer', minimum: 1, maximum: 1000 } }, required: ['q'] } do |_ctx, a|
            require 'find'
            root = a['path'].to_s.strip
            root = Dir.pwd if root.empty?
            pattern = a['q'].to_s
            regex = begin
              Regexp.new(pattern)
            rescue StandardError
              Regexp.new(Regexp.escape(pattern))
            end
            include_globs = Array(a['globs']).map(&:to_s)
            ignore_globs = Array(a['ignore']).map(&:to_s)
            limit = (a['limit'] || 200).to_i
            matches = []
            Find.find(root) do |path|
              break if matches.length >= limit
              next if File.directory?(path)

              rel = path.sub(%r{^#{Regexp.escape(root)}/?}, '')
              next if rel.start_with?('.git/')
              next if !include_globs.empty? && include_globs.none? { |g| File.fnmatch?(g, rel, File::FNM_EXTGLOB | File::FNM_PATHNAME) }
              next if ignore_globs.any? { |g| File.fnmatch?(g, rel, File::FNM_EXTGLOB | File::FNM_PATHNAME) }

              begin
                File.foreach(path, chomp: true).with_index do |line, idx|
                  if regex.match?(line)
                    matches << { path: rel, line_no: idx + 1, line: line }
                    break if matches.length >= limit
                  end
                end
              rescue StandardError
                next
              end
            end
            { root: File.expand_path(root), count: matches.length, matches: matches }
          end

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
