#!/usr/bin/env ruby
# frozen_string_literal: true

module Savant
  module Agent
    # Simple in-memory cancellation registry keyed by a string (e.g., "agent:name:user").
    module Cancel
      @mutex = Mutex.new
      @flags = {}

      module_function

      def key_for(agent_name:, user_id: nil)
        user = user_id && !user_id.to_s.empty? ? user_id.to_s : 'default'
        "agent:#{agent_name}:#{user}"
      end

      def key_for_run(agent_name:, run_id:, user_id: nil)
        user = user_id && !user_id.to_s.empty? ? user_id.to_s : 'default'
        "agent:#{agent_name}:run:#{run_id}:#{user}"
      end

      def request(key)
        @mutex.synchronize { @flags[key] = true }
        true
      end

      def clear(key)
        @mutex.synchronize { @flags.delete(key) }
        true
      end

      def signal?(key)
        @mutex.synchronize { !!@flags[key] }
      end
    end
  end
end
