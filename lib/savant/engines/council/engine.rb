#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'ops'

module Savant
  module Council
    class Engine
      def initialize
        @ops = Savant::Council::Ops.new
      end

      def server_info
        { name: 'council', version: Savant::VERSION, description: 'Multi-agent Council sessions with Chat/Council modes' }
      end

      # =========================
      # Session Management
      # =========================

      def session_create(title: nil, agents: [], user_id: nil, description: nil)
        @ops.session_create(title: title, agents: agents, user_id: user_id, description: description)
      end

      def sessions_list(limit: 50)
        @ops.sessions_list(limit: limit)
      end

      def session_get(id:)
        @ops.session_get(id: id)
      end

      def session_update(id:, title: nil, agents: nil, description: nil)
        @ops.session_update(id: id, title: title, agents: agents, description: description)
      end

      def session_delete(id:)
        @ops.session_delete(id: id)
      end

      def session_clear(id:)
        @ops.session_clear(id: id)
      end

      # =========================
      # Chat Mode Operations
      # =========================

      def append_user(session_id:, text:, user_id: nil)
        @ops.append_user(session_id: session_id, text: text, user_id: user_id)
      end

      def append_agent(session_id:, agent_name:, run_id: nil, text: nil, status: 'ok')
        @ops.append_agent(session_id: session_id, agent_name: agent_name, run_id: run_id, text: text, status: status)
      end

      def agent_step(session_id:, goal_text:, agent_name: nil)
        @ops.agent_step(session_id: session_id, goal_text: goal_text, agent_name: agent_name)
      end

      # =========================
      # Council Protocol Operations
      # =========================

      # Get available council roles
      def council_roles
        @ops.council_roles
      end

      # Get current session mode (chat or council)
      def session_mode(session_id:)
        @ops.session_mode(session_id: session_id)
      end

      # Escalate from chat to council mode
      def escalate_to_council(session_id:, query: nil, user_id: nil)
        @ops.escalate_to_council(session_id: session_id, query: query, user_id: user_id)
      end

      # Run the full council protocol
      def run_council(session_id:, run_id: nil, max_debate_rounds: 2)
        @ops.run_council_protocol(session_id: session_id, run_id: run_id, max_debate_rounds: max_debate_rounds)
      end

      # Return from council mode to chat mode
      def return_to_chat(session_id:, message: nil)
        @ops.return_to_chat(session_id: session_id, message: message)
      end

      # Get council status for a session
      def council_status(session_id:)
        @ops.council_status(session_id: session_id)
      end

      # Get a specific council run
      def get_council_run(run_id:)
        @ops.get_council_run(run_id: run_id)
      end

      # List council runs for a session
      def list_council_runs(session_id:, limit: 20)
        @ops.list_council_runs(session_id: session_id, limit: limit)
      end
    end
  end
end
