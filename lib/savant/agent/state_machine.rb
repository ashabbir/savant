#!/usr/bin/env ruby
# frozen_string_literal: true

module Savant
  module Agent
    # Tracks agent execution phases (Searching, Analyzing, Deciding, Finishing)
    # and detects when agents are stuck or inefficient.
    class StateMachine
      VALID_STATES = %i[init searching analyzing deciding finishing stuck_search stuck_analyze stuck_decide].freeze

      VALID_TRANSITIONS = {
        init: %i[searching deciding finishing],
        searching: %i[analyzing stuck_search finishing],
        analyzing: %i[deciding stuck_analyze finishing],
        deciding: %i[searching finishing stuck_decide],
        stuck_search: %i[finishing],
        stuck_analyze: %i[finishing],
        stuck_decide: %i[finishing],
        finishing: []
      }.freeze

      STATE_TIMEOUTS = {
        init: 5,
        searching: 60,
        analyzing: 30,
        deciding: 45,
        stuck_search: 10,
        stuck_analyze: 10,
        stuck_decide: 10,
        finishing: 5
      }.freeze

      STUCK_THRESHOLDS = {
        repeated_tool_calls: 3,
        steps_in_state: 5,
        same_search_queries: 2
      }.freeze

      attr_reader :current_state, :state_history, :step_count

      def initialize(initial_state: :init)
        raise "Invalid initial state: #{initial_state}" unless VALID_STATES.include?(initial_state)

        @current_state = initial_state
        @state_history = []
        @step_count = 0
        @state_entry_time = Time.now
        @state_step_count = 0
        @last_tools = []
        @last_queries = []
      end

      # Check if in a specific state
      def in_state?(name)
        current_state == name.to_sym
      end

      # Get allowed actions for current state
      def allowed_actions
        case current_state
        when :searching
          %w[context.fts_search context.memory_search]
        when :analyzing
          [] # No tool calls, just reasoning
        when :deciding
          %w[context.fts_search context.memory_search] # Can go back to search
        when :init, :finishing, :stuck_search, :stuck_analyze, :stuck_decide
          []
        else
          []
        end
      end

      # Get valid next states
      def next_states
        VALID_TRANSITIONS[current_state] || []
      end

      # Transition to a new state
      def transition_to(new_state, reason: nil)
        new_state = new_state.to_sym

        # Validate state
        unless VALID_STATES.include?(new_state)
          return { ok: false, error: "Invalid state: #{new_state}" }
        end

        # Validate transition
        unless VALID_TRANSITIONS[current_state].include?(new_state)
          return { ok: false, error: "Invalid transition: #{current_state} → #{new_state}" }
        end

        # Record transition in history
        entry = {
          step_num: @step_count,
          from_state: @current_state,
          to_state: new_state,
          reason: reason,
          duration_ms: state_duration_ms,
          timestamp: Time.now.utc.iso8601
        }
        @state_history << entry

        # Update state
        @current_state = new_state
        @state_entry_time = Time.now
        @state_step_count = 0

        { ok: true, from_state: entry[:from_state], to_state: new_state }
      end

      # Record a tool call within current state
      def record_tool_call(tool_name, args = {})
        @last_tools.unshift(tool_name)
        @last_tools = @last_tools.first(STUCK_THRESHOLDS[:repeated_tool_calls])

        # Track search queries for deduplication
        if %w[context.fts_search context.memory_search].include?(tool_name)
          query = args[:query] || args['query'] || ''
          @last_queries.unshift(query)
          @last_queries = @last_queries.first(STUCK_THRESHOLDS[:same_search_queries])
        end

        @state_history << {
          step_num: @step_count,
          state: @current_state,
          type: 'tool_call',
          tool_name: tool_name,
          args: args,
          timestamp: Time.now.utc.iso8601
        }
      end

      # Increment step counter
      def tick
        @step_count += 1
        @state_step_count += 1
      end

      # Check if agent is stuck
      def stuck?
        return false if in_state?(:finishing)

        # Rule 1: Same tool called N times consecutively
        if @last_tools.length >= STUCK_THRESHOLDS[:repeated_tool_calls]
          return true if @last_tools.uniq.length == 1
        end

        # Rule 2: Too many steps in current state
        return true if @state_step_count >= STUCK_THRESHOLDS[:steps_in_state]

        # Rule 3: State timeout exceeded
        return true if state_duration_ms > state_timeout_ms

        # Rule 4: Same search query repeated
        if @last_queries.length >= STUCK_THRESHOLDS[:same_search_queries]
          return true if @last_queries.uniq.length == 1 && @last_queries.first.to_s.length > 0
        end

        false
      end

      # Get suggestion for exiting current state
      def suggest_exit
        case current_state
        when :searching
          "Searched #{@state_step_count} times. Try: finish with the results you found."
        when :analyzing
          "Analysis is taking too long. You have enough information. Try: finish with your summary."
        when :deciding
          "Decision loop detected (#{@state_step_count} steps). Commit to an action or finish."
        else
          "No progress made. Use 'finish' with the best answer you have."
        end
      end

      # Get current state duration in milliseconds
      def state_duration_ms
        ((Time.now - @state_entry_time) * 1000).to_i
      end

      # Get timeout for current state
      def state_timeout_ms
        STATE_TIMEOUTS[current_state] * 1000
      end

      # Get inferred next state from tool choice
      def infer_state_from_tool(tool_name)
        case tool_name
        when 'context.fts_search', 'context.memory_search'
          :searching
        when nil
          :finishing
        else
          :deciding
        end
      end

      # Serialize to hash for logging/payload
      def to_h
        {
          current_state: current_state,
          duration_ms: state_duration_ms,
          step_count: @step_count,
          state_step_count: @state_step_count,
          history_length: state_history.length,
          stuck: stuck?,
          suggested_exit: stuck? ? suggest_exit : nil,
          allowed_actions: allowed_actions,
          next_states: next_states,
          last_tools: @last_tools,
          last_queries: @last_queries
        }
      end
    end
  end
end
