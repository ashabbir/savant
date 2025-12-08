#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../version'
require_relative 'ops'

module Savant
  module Agents
    # Engine exposes agents CRUD + run tools over MCP/Hub.
    class Engine
      def initialize
        @ops = Savant::Agents::Ops.new
      end

      def server_info
        { name: 'agents', version: Savant::VERSION, description: 'Savant Agents engine (CRUD + run)' }
      end

      # CRUD
      def list
        @ops.list
      end

      def get(name:)
        @ops.get(name: name)
      end

      def create(name:, persona:, driver:, rules: [], favorite: false)
        @ops.create(name: name, persona: persona, driver: driver, rules: rules, favorite: favorite)
      end

      def update(name:, persona: nil, driver: nil, rules: nil, favorite: nil)
        @ops.update(name: name, persona: persona, driver: driver, rules: rules, favorite: favorite)
      end

      def delete(name:)
        @ops.delete(name: name)
      end

      # Runs
      def run(name:, input:, max_steps: nil, dry_run: false, user_id: nil)
        @ops.run(name: name, input: input, max_steps: max_steps, dry_run: dry_run, user_id: user_id)
      end

      def runs_list(name:, limit: 50)
        @ops.runs_list(name: name, limit: limit)
      end

      def run_read(name:, run_id:)
        @ops.run_read(name: name, run_id: run_id)
      end

      def run_delete(name:, run_id:)
        @ops.run_delete(name: name, run_id: run_id)
      end

      def runs_clear_all(name:)
        @ops.runs_clear_all(name: name)
      end

      def run_cancel(name:, user_id: nil)
        @ops.run_cancel(name: name, user_id: user_id)
      end
    end
  end
end
