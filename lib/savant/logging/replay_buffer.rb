# frozen_string_literal: true

module Savant
  module Logging
    # Stores the last N tool invocations for debugging/replay purposes.
    class ReplayBuffer
      attr_reader :limit

      def initialize(limit: 25)
        @limit = [limit.to_i, 1].max
        @entries = []
        @mutex = Mutex.new
      end

      def push(entry)
        @mutex.synchronize do
          @entries << entry
          @entries.shift while @entries.size > @limit
        end
      end

      def entries
        @mutex.synchronize { @entries.dup }
      end
    end
  end
end
