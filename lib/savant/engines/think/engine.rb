#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'json'
require 'digest'
require 'fileutils'
require 'securerandom'
require_relative '../../version'
require_relative '../../framework/db'

module Savant
  module Think
    # Minimal deterministic orchestration engine for Think MCP tools.
    # Implements:
    # - plan(workflow:, params:)
    # - next(workflow:, step_id:, result_snapshot:)
    # - workflows_list(filter:)
    # - workflows_read(workflow:)
    # - limits
    # - runs_list / run_read / run_delete
    # - workflows_graph
    #
    # NOTE: Driver prompts have moved to the Drivers engine (drivers_get, drivers_list).
    # Workflows should explicitly include a step that calls drivers_get if they need
    # a driver prompt. The Think engine no longer auto-injects driver bootstrap steps.
    # rubocop:disable Metrics/ClassLength
    class Engine
      def initialize(env: ENV, db: nil)
        @env = env
        @base = resolve_base_path
        @root = File.join(@base, 'lib', 'savant', 'engines', 'think')
        @limits = load_think_limits
        @db = db || Savant::Framework::DB.new
      end

      # Return current limits/configuration
      attr_reader :limits

      # List saved workflow runs from .savant/state
      # @return [Hash] { runs: [ { workflow:, run_id:, completed:, next_step_id:, path:, updated_at: } ] }
      def runs_list
        dir = File.join(@base, '.savant', 'state')
        rows = []
        if Dir.exist?(dir)
          Dir.children(dir).select { |f| f.end_with?('.json') }.each do |fn|
            path = File.join(dir, fn)
            begin
              st = JSON.parse(read_text_utf8(path))
              wf = st['workflow'] || guess_workflow_from_filename(fn)
              rid = st['run_id'] || guess_run_id_from_filename(fn)
              done = Array(st['completed']).length
              nxt = next_ready_step_id(st)
              rows << { workflow: wf, run_id: rid, completed: done, next_step_id: nxt, path: path, updated_at: File.mtime(path).utc.iso8601 }
            rescue StandardError
              next
            end
          end
        end
        { runs: rows }
      end

      # Read a run state by workflow and run_id
      def run_read(workflow:, run_id:)
        st = read_state(workflow, run_id)
        { state: st }
      end

      # Delete a run state
      def run_delete(workflow:, run_id:)
        path = state_path_for(workflow, run_id)
        if File.exist?(path)
          FileUtils.rm_f(path)
          { ok: true, deleted: true }
        else
          { ok: true, deleted: false }
        end
      end

      # Build graph for a workflow
      # @return [Hash] { nodes: [ { id:, call:, deps: [] } ], order: [] }
      def workflows_graph(workflow:)
        wf = load_workflow(workflow)
        g = build_graph(wf)
        nodes = (wf['steps'] || []).map { |s| { id: s['id'], call: s['call'], deps: Array(s['deps']).map(&:to_s) } }
        { nodes: nodes, order: topo_order(g) }
      end

      # Validate a workflow graph for Think format
      # @param graph [Hash] { nodes: [ { id:, call:, deps?:[], input_template?:{}, capture_as?:string } ], edges?: [ { source:, target: } ] }
      # Returns { ok:, errors: [] }
      def workflows_validate_graph(graph:)
        errs = validate_think_graph(graph)
        { ok: errs.empty?, errors: errs }
      end

      # Create a workflow from a Think graph in database
      def workflows_create_from_graph(workflow:, graph:)
        id = normalize_workflow_id(workflow)
        raise 'INVALID_ID' if id.nil? || id.empty?

        existing = @db.get_think_workflow(id)
        raise 'ALREADY_EXISTS' if existing

        # Validate and build workflow from graph
        errs = validate_think_graph(graph)
        raise "VALIDATION_FAILED: #{errs.join('; ')}" unless errs.empty?

        h = build_workflow_from_graph(id, graph)
        @db.create_think_workflow(
          workflow_id: id,
          name: h['name'],
          description: h['description'],
          version: h['version'],
          steps: h['steps']
        )
        { ok: true, id: id }
      end

      # Update existing workflow from graph in database
      def workflows_update_from_graph(workflow:, graph:)
        id = normalize_workflow_id(workflow)
        raise 'INVALID_ID' if id.nil? || id.empty?

        existing = @db.get_think_workflow(id)
        raise 'WORKFLOW_NOT_FOUND' unless existing

        # Validate and build workflow from graph
        errs = validate_think_graph(graph)
        raise "VALIDATION_FAILED: #{errs.join('; ')}" unless errs.empty?

        h = build_workflow_from_graph(id, graph)
        @db.update_think_workflow(
          workflow_id: id,
          name: h['name'],
          description: h['description'],
          version: h['version'],
          steps: h['steps']
        )
        { ok: true, id: id }
      end

      # Write raw YAML for a workflow (full replacement) to database
      def workflows_write_yaml(workflow:, yaml:)
        id = normalize_workflow_id(workflow)
        raise 'INVALID_ID' if id.nil? || id.empty?

        # Parse YAML to extract fields
        h = safe_yaml(yaml.to_s)
        raise 'INVALID_YAML: steps required' unless h['steps'].is_a?(Array) && h['steps'].any?

        existing = @db.get_think_workflow(id)
        raise 'WORKFLOW_NOT_FOUND' unless existing

        @db.update_think_workflow(
          workflow_id: id,
          name: h['name'],
          description: h['description'],
          version: (h['version'] || existing['version'].to_i + 1).to_i,
          steps: h['steps']
        )
        { ok: true, id: id }
      end

      # Delete a workflow from database
      def workflows_delete(workflow:)
        id = normalize_workflow_id(workflow)
        existing = @db.get_think_workflow(id)
        raise 'WORKFLOW_NOT_FOUND' unless existing

        deleted = @db.delete_think_workflow(id)
        { ok: true, deleted: deleted }
      end

      def guess_workflow_from_filename(filename)
        base = File.basename(filename, '.json')
        wf, _rid = base.split('__', 2)
        wf
      end

      def guess_run_id_from_filename(filename)
        base = File.basename(filename, '.json')
        _wf, rid = base.split('__', 2)
        rid
      end

      # Plan a workflow and return the first instruction and initial state
      # @param workflow [String]
      # @param params [Hash]
      # @param run_id [String, nil] optional explicit run identifier
      # @param start_fresh [Boolean] when true, remove any prior state for this run_id
      # @return [Hash] { instruction:, state:, done: false, run_id: }
      #
      # NOTE: Driver bootstrap is no longer auto-injected. Workflows should explicitly
      # include a step that calls drivers_get if they need a driver prompt.
      def plan(workflow:, params: {}, run_id: nil, start_fresh: true)
        wf = load_workflow(workflow)
        graph = build_graph(wf)
        order = topo_order(graph)
        raise 'EMPTY_WORKFLOW' if order.empty?

        nodes = wf['steps'].map { |s| [s['id'], s] }.to_h
        first = order.find { |sid| (graph[sid] || []).empty? || (nodes[sid]['deps'] || []).empty? } || order.first
        rid = normalize_run_id(run_id) || generate_run_id(workflow)
        # Reset state for this run when requested
        if start_fresh
          path = state_path_for(workflow, rid)
          FileUtils.rm_f(path)
        end
        st = {
          'workflow' => workflow,
          'params' => params || {},
          'completed' => [],
          'order' => order,
          'vars' => {},
          'nodes' => nodes,
          'run_id' => rid
        }
        write_state(workflow, rid, st)
        { instruction: instruction_for(nodes[first]), state: st, run_id: rid, done: false }
      end

      # Advance workflow by recording result and computing next instruction
      # @param workflow [String]
      # @param run_id [String]
      # @param step_id [String]
      # @param result_snapshot [Hash]
      # @return [Hash] { instruction:, done: false } or { done: true, summary: }
      def next(workflow:, run_id:, step_id:, result_snapshot: {})
        st = read_state(workflow, run_id)
        nodes = st['nodes'] || {}
        step = nodes[step_id]
        raise 'UNKNOWN_STEP' unless step

        # capture variable if requested
        cap = step['capture_as']
        st['vars'][cap] = validate_payload(result_snapshot) if cap
        st['completed'] |= [step_id]
        write_state(workflow, run_id, st)

        nxt_id = next_ready_step_id(st)
        if nxt_id
          { instruction: instruction_for(nodes[nxt_id]), done: false }
        else
          { done: true, summary: 'All steps completed.' }
        end
      end

      # List workflows from database
      # @return [Hash] { workflows: [ { id:, version:, desc:, name: } ] }
      def workflows_list(filter: nil)
        rows = @db.list_think_workflows(filter: filter)
        workflows = rows.map do |row|
          {
            id: row['workflow_id'],
            version: (row['version'] || 1).to_s,
            desc: row['description'] || '',
            name: (row['name'] || row['workflow_id']).to_s
          }
        end
        { workflows: workflows }
      end

      # Read raw workflow YAML from database
      def workflows_read(workflow:)
        row = @db.get_think_workflow(workflow)
        raise 'WORKFLOW_NOT_FOUND' unless row

        # Reconstruct YAML from DB record
        h = {
          'id' => row['workflow_id'],
          'name' => row['name'],
          'description' => row['description'],
          'version' => row['version'].to_i,
          'steps' => row['steps']
        }
        { workflow_yaml: YAML.dump(h) }
      end

      # For MCP initialize handshake
      def server_info
        {
          name: 'savant-think',
          version: Savant::VERSION,
          description: 'Think MCP: workflow orchestration via plan/next/workflows/*. Call think_workflows_list to discover workflows, then use think_plan to start a run. For driver prompts, use the Drivers engine (drivers_get, drivers_list).'
        }
      end

      private

      def resolve_base_path
        base = @env['SAVANT_PATH']
        return base unless base.nil? || base.strip.empty?

        File.expand_path('../../../..', __dir__)
      end

      def safe_yaml(str)
        YAML.safe_load(str, permitted_classes: [], aliases: true) || {}
      end

      # Read a text file as UTF-8, tolerating BOM and invalid bytes.
      def read_text_utf8(path)
        File.open(path, 'r:bom|utf-8', &:read)
      rescue ArgumentError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
        data = File.binread(path)
        # Force-convert to UTF-8, replacing invalid/undefined bytes
        data.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
      end

      def sync_workflows_to_root
        src_dir = File.join(@root, 'workflows')
        dst_dir = File.join(@base, 'workflows')
        return unless Dir.exist?(src_dir)

        FileUtils.mkdir_p(dst_dir)
        Dir.glob(File.join(src_dir, '*.{yaml,yml}')).each do |src_path|
          dst_path = File.join(dst_dir, File.basename(src_path))
          next if File.exist?(dst_path) && File.mtime(dst_path) >= File.mtime(src_path)

          FileUtils.cp(src_path, dst_path)
        end
      rescue StandardError
        # best effort sync – ignore errors
      end

      def load_think_limits
        cfg_path = File.join(@base, 'config', 'think.yml')
        h = File.exist?(cfg_path) ? safe_yaml(File.read(cfg_path)) : {}
        payload = h['payload'] || {}
        logging = h['logging'] || {}
        {
          max_snapshot_bytes: (payload['max_snapshot_bytes'] || 50_000).to_i,
          max_string_bytes: (payload['max_string_bytes'] || 5_000).to_i,
          truncation_strategy: (payload['truncation_strategy'] || 'summarize').to_s,
          log_payload_sizes: !logging.fetch('log_payload_sizes', true).nil?,
          warn_threshold_bytes: (logging['warn_threshold_bytes'] || 40_000).to_i
        }
      rescue StandardError
        { max_snapshot_bytes: 50_000, max_string_bytes: 5_000, truncation_strategy: 'summarize',
          log_payload_sizes: true, warn_threshold_bytes: 40_000 }
      end

      def load_workflow(id)
        row = @db.get_think_workflow(id)
        raise 'WORKFLOW_NOT_FOUND' unless row

        steps = row['steps']
        raise 'YAML_SCHEMA_VIOLATION: steps missing' unless steps.is_a?(Array) && steps.any?

        steps.each do |s|
          s_id = s['id'] || s[:id]
          s_call = s['call'] || s[:call]
          raise 'YAML_SCHEMA_VIOLATION: id required' unless s_id.is_a?(String) && !s_id.empty?
          raise 'YAML_SCHEMA_VIOLATION: call required' unless s_call.is_a?(String) && !s_call.empty?
        end

        # Return hash compatible with workflow structure
        {
          'id' => row['workflow_id'],
          'name' => row['name'],
          'description' => row['description'],
          'version' => row['version'].to_i,
          'steps' => steps
        }
      end

      def resolve_workflow_path(id)
        dir = File.join(@root, 'workflows')
        yml = File.join(dir, "#{id}.yml")
        yaml = File.join(dir, "#{id}.yaml")
        return yaml if File.exist?(yaml)
        return yml if File.exist?(yml)

        nil
      end

      def workflows_dir
        File.join(@root, 'workflows')
      end

      def workflow_path_for(id)
        File.join(workflows_dir, "#{id}.yaml")
      end

      def normalize_workflow_id(id)
        return nil if id.nil?

        s = id.to_s.strip
        return '' if s.empty?

        s.gsub(/[^A-Za-z0-9_.-]/, '_')
      end

      # Build adjacency list graph id => deps
      def build_graph(workflow_hash)
        g = {}
        ids = workflow_hash['steps'].map { |s| s['id'] }
        workflow_hash['steps'].each do |s|
          deps = Array(s['deps']).map(&:to_s)
          # keep only known ids
          g[s['id']] = deps.select { |d| ids.include?(d) }
        end
        g
      end

      # Build workflow hash from graph (for DB storage)
      def build_workflow_from_graph(id, graph)
        # Build deps from edges if provided; otherwise rely on nodes.deps
        nodes = Array(graph['nodes']).map { |n| { 'id' => n['id'].to_s, 'call' => n['call'].to_s, 'deps' => Array(n['deps']).map(&:to_s), 'input_template' => n['input_template'], 'capture_as' => n['capture_as'] } }
        edges = Array(graph['edges']).map { |e| [e['source'].to_s, e['target'].to_s] }
        if edges.any?
          indeg = Hash.new(0)
          deps = Hash.new { |h, k| h[k] = [] }
          nodes.each { |n| indeg[n['id']] = 0 }
          edges.each do |(u, v)|
            next unless indeg.key?(u) && indeg.key?(v)

            deps[v] << u unless deps[v].include?(u)
            indeg[v] += 1
          end
          nodes.each { |n| n['deps'] = deps[n['id']] }
        end

        desc = graph['description'] || graph[:description]
        desc = desc.to_s if desc
        name = graph['name'] || graph[:name]
        name = name.to_s unless name.nil?
        version = graph['version'] || graph[:version]
        version = version.to_i if version
        version = 1 if version.nil? || version <= 0

        steps = nodes.map do |n|
          h = { 'id' => n['id'], 'call' => n['call'] }
          d = Array(n['deps']).map(&:to_s)
          h['deps'] = d unless d.empty?
          it = n['input_template']
          h['input_template'] = it if it.is_a?(Hash) && !it.empty?
          cap = n['capture_as']
          h['capture_as'] = cap if cap.is_a?(String) && !cap.empty?
          h
        end
        {
          'id' => id,
          'name' => name || id,
          'description' => desc || '',
          'version' => version,
          'steps' => steps
        }
      end

      # Convert Think graph to YAML (legacy, still used for some cases)
      def think_graph_to_yaml(id:, graph:)
        errs = validate_think_graph(graph)
        raise "VALIDATION_FAILED: #{errs.join('; ')}" unless errs.empty?

        payload = build_workflow_from_graph(id, graph)
        YAML.dump(payload)
      end

      # Validate Think graph semantics
      def validate_think_graph(graph)
        errs = []
        nodes = Array(graph['nodes'])
        errs << 'no nodes' if nodes.empty?
        ids = nodes.map { |n| (n['id'] || '').to_s }
        errs << 'node id missing' if ids.any?(&:empty?)
        dups = ids.group_by { |x| x }.select { |_k, v| v.size > 1 }.keys
        errs << "duplicate ids: #{dups.join(', ')}" unless dups.empty?
        nodes.each do |n|
          call = (n['call'] || '').to_s
          errs << "call missing for #{n['id'] || ''}" if call.empty?
        end
        # Graph connectivity/cycle checks use edges if present, else deps
        edges = Array(graph['edges']).map { |e| [e['source'].to_s, e['target'].to_s] }
        adj = Hash.new { |h, k| h[k] = [] }
        indeg = Hash.new(0)
        ids.each { |i| indeg[i] = 0 }
        if edges.any?
          edges.each do |(u, v)|
            next unless indeg.key?(u) && indeg.key?(v)

            adj[u] << v
            indeg[v] += 1
          end
        else
          nodes.each do |n|
            Array(n['deps']).each do |dep|
              d = dep.to_s
              next unless indeg.key?(d)

              adj[d] << n['id']
              indeg[n['id']] += 1
            end
          end
        end
        starts = ids.select { |i| indeg[i].zero? }
        errs << 'graph must have at least one start node' if starts.empty?
        # Reachability
        reachable = {}
        stack = starts.dup
        until stack.empty?
          cur = stack.pop
          next if reachable[cur]

          reachable[cur] = true
          (adj[cur] || []).each { |n| stack << n }
        end
        unreachable = ids.reject { |i| reachable[i] }
        errs << "unreachable nodes: #{unreachable.join(', ')}" unless unreachable.empty?
        # Cycle check (Kahn)
        indeg2 = indeg.dup
        q = ids.select { |i| indeg2[i].zero? }
        count = 0
        until q.empty?
          u = q.shift
          count += 1
          (adj[u] || []).each do |v|
            indeg2[v] -= 1
            q << v if indeg2[v].zero?
          end
        end
        errs << 'cycles not allowed' unless count == ids.length
        errs
      end

      def write_yaml_with_backup(path, yaml_text)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
        if File.exist?(path)
          ts = Time.now.utc.strftime('%Y%m%d%H%M%S')
          FileUtils.cp(path, "#{path}.bak#{ts}")
        end
        tmp = "#{path}.tmp"
        File.open(tmp, 'w:UTF-8') { |f| f.write(yaml_text) }
        FileUtils.mv(tmp, path)
      end

      # Topological order using Kahn's algorithm
      def topo_order(graph)
        indeg = Hash.new(0)
        graph.each_value do |ds|
          ds.each { |d| indeg[d] += 1 }
        end
        q = []
        graph.each_key { |k| q << k if indeg[k].zero? }
        out = []
        until q.empty?
          n = q.shift
          out << n
          (graph[n] || []).each do |m|
            indeg[m] -= 1
            q << m if indeg[m].zero?
          end
        end
        out
      end

      def instruction_for(step)
        {
          step_id: step['id'],
          call: step['call'],
          input_template: step['input_template'] || {},
          capture_as: step['capture_as'],
          success_schema: step['success_schema'],
          rationale: step['rationale'],
          done: false
        }
      end

      def validate_payload(snapshot)
        snapshot_utf8 = sanitize_utf8(snapshot)
        begin
          json = JSON.generate(snapshot_utf8)
        rescue StandardError
          return summarize_structure(snapshot_utf8)
        end
        sz = json.bytesize
        @limits[:warn_threshold_bytes]
        max = @limits[:max_snapshot_bytes]
        if @limits[:log_payload_sizes]
          # Avoid requiring logger wiring here; annotate size in the snapshot itself
        end
        return snapshot_utf8 if sz <= max

        # Truncate / summarize
        truncate_snapshot(snapshot_utf8, max)
      end

      def truncate_snapshot(obj, max_bytes, string_max: @limits[:max_string_bytes])
        case obj
        when String
          return obj if obj.bytesize <= string_max

          head = obj.byteslice(0, string_max)
          "#{head}…(truncated #{obj.bytesize - head.bytesize} bytes)"
        when Array
          out = []
          obj.each do |el|
            out << truncate_snapshot(el, max_bytes, string_max: string_max)
            break if JSON.generate(out).bytesize > max_bytes
          end
          out << "…(#{obj.length - out.length} more items)" if out.length < obj.length
          out
        when Hash
          out = {}
          obj.each do |k, v|
            out[k] = truncate_snapshot(v, max_bytes, string_max: string_max)
            break if JSON.generate(out).bytesize > max_bytes
          end
          out['_truncated'] = true if out.keys.sort != obj.keys.sort
          out
        else
          obj
        end
      rescue StandardError
        summarize_structure(obj)
      end

      def summarize_structure(obj)
        case obj
        when Array
          { '_summary' => 'array', 'length' => obj.length }
        when Hash
          { '_summary' => 'object', 'keys' => obj.keys.take(20), 'key_count' => obj.keys.length }
        when String
          { '_summary' => 'string', 'bytes' => obj.bytesize }
        else
          { '_summary' => obj.class.name }
        end
      end

      def sanitize_utf8(obj)
        case obj
        when String
          obj.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
        when Array
          obj.map { |el| sanitize_utf8(el) }
        when Hash
          obj.each_with_object({}) do |(k, v), h|
            kk = k.is_a?(String) ? k.encode('UTF-8', invalid: :replace, undef: :replace, replace: '') : k
            h[kk] = sanitize_utf8(v)
          end
        else
          obj
        end
      rescue StandardError
        obj
      end

      def next_ready_step_id(state)
        done = state['completed'] || []
        order = state['order'] || []
        nodes = state['nodes'] || {}
        order.find do |sid|
          next false if done.include?(sid)

          deps = Array(nodes[sid]['deps'])
          (deps - done).empty?
        end
      end

      def state_path_for(workflow, run_id)
        dir = File.join(@base, '.savant', 'state')
        FileUtils.mkdir_p(dir)
        rid = normalize_run_id(run_id) || generate_run_id(workflow)
        File.join(dir, "#{workflow}__#{rid}.json")
      end

      def read_state(workflow, run_id)
        path = state_path_for(workflow, run_id)
        return {} unless File.exist?(path)

        JSON.parse(read_text_utf8(path))
      end

      def write_state(workflow, run_id, obj)
        path = state_path_for(workflow, run_id)
        tmp = "#{path}.tmp"
        File.open(tmp, 'w:UTF-8') { |f| f.write(JSON.pretty_generate(obj)) }
        FileUtils.mv(tmp, path)
      end

      def generate_run_id(workflow)
        ts = Time.now.utc.strftime('%Y%m%d%H%M%S')
        rnd = SecureRandom.hex(4)
        base = Digest::SHA256.hexdigest("#{workflow}|#{ts}|#{rnd}")[0, 8]
        "#{ts}-#{base}"
      end

      def normalize_run_id(run_id)
        return nil if run_id.nil?

        s = run_id.to_s.strip
        return nil if s.empty?

        s.gsub(/[^A-Za-z0-9_.-]/, '_')
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
