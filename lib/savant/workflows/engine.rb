#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'json'
require 'fileutils'

module Savant
  module Workflows
    # File-backed workflow CRUD + YAML<->Graph conversion per PRD.
    # YAML format:
    # id, title, description, steps: [{ id, type: 'tool'|'llm'|'return', engine?, method?, args?, prompt?, value? }]
    class Engine
      def initialize(env: ENV)
        @env = env
        @base = resolve_base_path
        @dir = File.join(@base, 'workflows')
        FileUtils.mkdir_p(@dir)
      end

      # List workflows: { workflows: [ { id, title, mtime } ] }
      def list
        rows = Dir.children(@dir).select { |f| f.end_with?('.yaml', '.yml') }.sort.map do |fn|
          id = File.basename(fn, File.extname(fn))
          path = File.join(@dir, fn)
          title = begin
            meta = safe_yaml(read_text_utf8(path))
            (meta['title'] || id).to_s
          rescue StandardError
            id
          end
          { id: id, title: title, mtime: File.mtime(path).utc.iso8601 }
        end
        { workflows: rows }
      end

      # Read YAML + graph for UI
      def read(id:)
        path = resolve_path(id)
        raise 'WORKFLOW_NOT_FOUND' unless path

        yaml_text = read_text_utf8(path)
        obj = safe_yaml(yaml_text)
        { yaml: yaml_text, graph: yaml_to_graph(obj) }
      end

      # Validate a graph without saving
      # Returns { ok: boolean, errors: [string] }
      def validate(graph:)
        errs = validate_graph(graph)
        { ok: errs.empty?, errors: errs }
      end

      # Create a new workflow from graph
      def create(id:, graph:)
        idn = normalize_id(id)
        raise 'INVALID_ID' if idn.nil? || idn.empty?

        path = File.join(@dir, "#{idn}.yaml")
        raise 'ALREADY_EXISTS' if File.exist?(path)

        write_yaml_with_backup(path, graph_to_yaml(id: idn, graph: graph))
        { ok: true, id: idn }
      end

      # Update existing workflow from graph
      def update(id:, graph:)
        idn = normalize_id(id)
        raise 'INVALID_ID' if idn.nil? || idn.empty?

        path = File.join(@dir, "#{idn}.yaml")
        raise 'WORKFLOW_NOT_FOUND' unless File.exist?(path)

        write_yaml_with_backup(path, graph_to_yaml(id: idn, graph: graph))
        { ok: true, id: idn }
      end

      # Delete workflow YAML
      def delete(id:)
        idn = normalize_id(id)
        path = resolve_path(idn)
        raise 'WORKFLOW_NOT_FOUND' unless path

        FileUtils.rm_f(path)
        { ok: true, deleted: true }
      end

      # Server info for hub status
      def server_info
        { name: 'savant-workflows', version: '1.0.0', description: 'Workflow CRUD + YAML<->Graph for Dashboard Builder' }
      end

      private

      def resolve_base_path
        base = @env['SAVANT_PATH']
        return base unless base.nil? || base.strip.empty?

        File.expand_path('../../..', __dir__)
      end

      def read_text_utf8(path)
        File.open(path, 'r:bom|utf-8', &:read)
      rescue ArgumentError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
        data = File.binread(path)
        data.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
      end

      def safe_yaml(str)
        YAML.safe_load(str, permitted_classes: [], aliases: true) || {}
      end

      def resolve_path(id)
        c = normalize_id(id)
        y1 = File.join(@dir, "#{c}.yaml")
        y2 = File.join(@dir, "#{c}.yml")
        return y1 if File.exist?(y1)
        return y2 if File.exist?(y2)

        nil
      end

      def normalize_id(id)
        return nil if id.nil?

        s = id.to_s.strip
        return '' if s.empty?

        s.gsub(/[^A-Za-z0-9_.-]/, '_')
      end

      # YAML -> Graph (best-effort; edges inferred by sequence)
      def yaml_to_graph(obj)
        steps = Array(obj['steps'])
        nodes = steps.map do |s|
          t = (s['type'] || '').to_s
          data = case t
                 when 'tool' then { 'engine' => s['engine'], 'method' => s['method'], 'args' => s['args'] || {} }
                 when 'llm' then { 'prompt' => s['prompt'] }
                 when 'return' then { 'value' => s['value'] }
                 else {}
                 end
          { 'id' => s['id'].to_s, 'type' => t, 'data' => data }
        end
        edges = []
        (0...(nodes.length - 1)).each do |i|
          edges << { 'source' => nodes[i]['id'], 'target' => nodes[i + 1]['id'] }
        end
        { 'nodes' => nodes, 'edges' => edges }
      end

      # Graph -> YAML text (with validation)
      def graph_to_yaml(id:, graph:)
        errs = validate_graph(graph)
        raise "VALIDATION_FAILED: #{errs.join('; ')}" unless errs.empty?

        ordered_ids = topo_sort(graph)
        node_map = Hash[(graph['nodes'] || []).map { |n| [n['id'].to_s, n] }]
        steps = ordered_ids.map do |sid|
          n = node_map[sid]
          t = n['type'].to_s
          case t
          when 'tool'
            { 'id' => sid, 'type' => 'tool', 'engine' => strf(n.dig('data', 'engine')), 'method' => strf(n.dig('data', 'method')), 'args' => n.dig('data', 'args') || {} }
          when 'llm'
            { 'id' => sid, 'type' => 'llm', 'prompt' => strf(n.dig('data', 'prompt')) }
          when 'return'
            { 'id' => sid, 'type' => 'return', 'value' => n.dig('data', 'value') }
          else
            raise "UNKNOWN_NODE_TYPE: #{t}"
          end
        end
        h = { 'id' => id, 'title' => id, 'description' => '', 'steps' => steps }
        YAML.dump(h)
      end

      def strf(v)
        v.nil? ? '' : v.to_s
      end

      def validate_graph(graph)
        nodes = Array(graph['nodes']).map { |n| { id: n['id'].to_s, type: n['type'].to_s, data: n['data'] || {} } }
        edges = Array(graph['edges']).map { |e| { source: e['source'].to_s, target: e['target'].to_s } }
        errs = []
        # Unique ids
        ids = nodes.map { |n| n[:id] }
        dups = ids.group_by { |x| x }.select { |_k, v| v.size > 1 }.keys
        errs << "duplicate ids: #{dups.join(', ')}" unless dups.empty?
        errs << 'no nodes' if nodes.empty?
        # Required fields by type
        nodes.each do |n|
          case n[:type]
          when 'tool'
            errs << "tool.engine missing for #{n[:id]}" if strf(n[:data]['engine']).empty?
            errs << "tool.method missing for #{n[:id]}" if strf(n[:data]['method']).empty?
          when 'llm'
            errs << "llm.prompt missing for #{n[:id]}" if strf(n[:data]['prompt']).empty?
          when 'return'
            errs << "return.value missing for #{n[:id]}" if n[:data]['value'].nil?
          else
            errs << "unknown type for #{n[:id]}"
          end
        end
        # Build adjacency
        adj = Hash.new { |h, k| h[k] = [] }
        indeg = Hash.new(0)
        ids.each { |i| indeg[i] = 0 }
        edges.each do |e|
          next unless ids.include?(e[:source]) && ids.include?(e[:target])

          adj[e[:source]] << e[:target]
          indeg[e[:target]] += 1
        end
        # Connectivity: exactly one start and reachable all nodes
        starts = ids.select { |i| indeg[i].zero? }
        errs << 'graph must have exactly one start node' unless starts.length == 1
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
        # Cycles: Kahn topo
        unless errs.any? { |e| e.include?('graph must have exactly one start') }
          cycle = has_cycle?(ids, adj, indeg.dup)
          errs << 'cycles not allowed' if cycle
        end
        errs
      end

      def topo_sort(graph)
        nodes = Array(graph['nodes']).map { |n| n['id'].to_s }
        edges = Array(graph['edges']).map { |e| [e['source'].to_s, e['target'].to_s] }
        adj = Hash.new { |h, k| h[k] = [] }
        indeg = Hash.new(0)
        nodes.each { |i| indeg[i] = 0 }
        edges.each do |(u, v)|
          next unless nodes.include?(u) && nodes.include?(v)

          adj[u] << v
          indeg[v] += 1
        end
        q = nodes.select { |i| indeg[i].zero? }
        order = []
        until q.empty?
          u = q.shift
          order << u
          (adj[u] || []).each do |v|
            indeg[v] -= 1
            q << v if indeg[v].zero?
          end
        end
        raise 'CYCLE_DETECTED' unless order.length == nodes.length

        order
      end

      def has_cycle?(nodes, adj, indeg)
        q = nodes.select { |i| indeg[i].zero? }
        count = 0
        until q.empty?
          u = q.shift
          count += 1
          (adj[u] || []).each do |v|
            indeg[v] -= 1
            q << v if indeg[v].zero?
          end
        end
        count != nodes.length
      end

      def write_yaml_with_backup(path, yaml_text)
        if File.exist?(path)
          ts = Time.now.utc.strftime('%Y%m%d%H%M%S')
          FileUtils.cp(path, "#{path}.bak#{ts}")
        end
        tmp = "#{path}.tmp"
        File.open(tmp, 'w:UTF-8') { |f| f.write(yaml_text) }
        FileUtils.mv(tmp, path)
      end
    end
  end
end
