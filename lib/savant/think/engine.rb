#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'json'
require 'digest'
require 'fileutils'

module Savant
  module Think
    # Minimal deterministic orchestration engine for Think MCP tools.
    # Implements:
    # - driver_prompt(version:)
    # - plan(workflow:, params:)
    # - next(workflow:, step_id:, result_snapshot:)
    # - workflows_list(filter:)
    # - workflows_read(workflow:)
    class Engine
      def initialize(env: ENV)
        @env = env
        @base = resolve_base_path
        @root = File.join(@base, 'lib', 'savant', 'think')
      end

      # Return prompt markdown for a version from prompts.yml
      # @return [Hash] { version:, hash:, prompt_md: }
      def driver_prompt(version: nil)
        reg_path = File.join(@root, 'prompts.yml')
        data = safe_yaml(File.read(reg_path))
        versions = data['versions'] || {}
        ver = version && versions[version] ? version : versions.keys.last
        raise 'PROMPT_NOT_FOUND' unless ver && versions[ver]

        path = versions[ver]
        # Resolve relative to lib/savant/think/
        p_path = File.join(@root, path)
        md = File.read(p_path)
        { version: ver, hash: "sha256:#{Digest::SHA256.hexdigest(md)}", prompt_md: md }
      end

      # Plan a workflow and return the first instruction and initial state
      # @return [Hash] { instruction:, state:, done: false }
      def plan(workflow:, params: {})
        wf = load_workflow(workflow)
        graph = build_graph(wf)
        order = topo_order(graph)
        raise 'EMPTY_WORKFLOW' if order.empty?

        nodes = wf['steps'].map { |s| [s['id'], s] }.to_h
        first = order.find { |sid| (graph[sid] || []).empty? || (nodes[sid]['deps'] || []).empty? } || order.first
        st = {
          'workflow' => workflow,
          'params' => params || {},
          'completed' => [],
          'order' => order,
          'vars' => {},
          'nodes' => nodes
        }
        write_state(workflow, st)
        { instruction: instruction_for(nodes[first]), state: st, done: false }
      end

      # Advance workflow by recording result and computing next instruction
      # @return [Hash] { instruction:, done: false } or { done: true, summary: }
      def next(workflow:, step_id:, result_snapshot: {})
        st = read_state(workflow)
        nodes = st['nodes'] || {}
        step = nodes[step_id]
        raise 'UNKNOWN_STEP' unless step

        # capture variable if requested
        cap = step['capture_as']
        st['vars'][cap] = result_snapshot if cap
        st['completed'] |= [step_id]
        write_state(workflow, st)

        nxt_id = next_ready_step_id(st)
        if nxt_id
          { instruction: instruction_for(nodes[nxt_id]), done: false }
        else
          { done: true, summary: 'All steps completed.' }
        end
      end

      # List workflows from filesystem
      # @return [Hash] { workflows: [ { id:, version:, desc: } ] }
      def workflows_list(filter: nil)
        dir = File.join(@root, 'workflows')
        entries = Dir.exist?(dir) ? Dir.children(dir).select { |f| f.end_with?('.yaml', '.yml') } : []
        rows = entries.map do |fn|
          id = File.basename(fn, File.extname(fn))
          next if filter && !id.include?(filter.to_s)

          h = safe_yaml(File.read(File.join(dir, fn)))
          { id: id, version: (h['version'] || '1.0').to_s, desc: h['description'] || '' }
        end
        { workflows: rows.compact }
      end

      # Read raw workflow YAML
      def workflows_read(workflow:)
        path = File.join(@root, 'workflows', "#{workflow}.yaml")
        raise 'WORKFLOW_NOT_FOUND' unless File.exist?(path)

        { workflow_yaml: File.read(path) }
      end

      # For MCP initialize handshake
      def server_info
        { name: 'savant-think', version: '1.0.0', description: 'Think MCP: plan/next/driver_prompt/workflows/*' }
      end

      private

      def resolve_base_path
        base = @env['SAVANT_PATH']
        return base unless base.nil? || base.strip.empty?

        File.expand_path('../../..', __dir__)
      end

      def safe_yaml(str)
        YAML.safe_load(str, permitted_classes: [], aliases: true) || {}
      end

      def load_workflow(id)
        path = File.join(@root, 'workflows', "#{id}.yaml")
        raise 'WORKFLOW_NOT_FOUND' unless File.exist?(path)

        h = safe_yaml(File.read(path))
        steps = h['steps']
        raise 'YAML_SCHEMA_VIOLATION: steps missing' unless steps.is_a?(Array) && steps.any?

        steps.each do |s|
          raise 'YAML_SCHEMA_VIOLATION: id required' unless s['id'].is_a?(String) && !s['id'].empty?
          raise 'YAML_SCHEMA_VIOLATION: call required' unless s['call'].is_a?(String) && !s['call'].empty?
        end
        h
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

      def state_path_for(workflow)
        dir = File.join(@base, '.savant', 'state')
        FileUtils.mkdir_p(dir)
        File.join(dir, "#{workflow}.json")
      end

      def read_state(workflow)
        path = state_path_for(workflow)
        return {} unless File.exist?(path)

        JSON.parse(File.read(path))
      end

      def write_state(workflow, obj)
        path = state_path_for(workflow)
        tmp = "#{path}.tmp"
        File.write(tmp, JSON.pretty_generate(obj))
        FileUtils.mv(tmp, path)
      end
    end
  end
end
