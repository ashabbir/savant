#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'time'
require 'fileutils'

module Savant
  module Logging
    # Thread-safe in-memory + file-backed event recorder with simple SSE fanout.
    # - Keeps a rolling in-memory buffer (default 10_000 events)
    # - Writes JSON lines to a rotating file (logs/savant.log by default)
    # - Provides a subscribe API for streaming events to SSE clients
    class EventRecorder
      DEFAULT_MAX = 10_000
      DEFAULT_MAX_BYTES = 5 * 1024 * 1024 # 5MB simple size-based rotation

      def self.global
        @global ||= new
      end

      def initialize(max_events: DEFAULT_MAX, file_path: nil, max_bytes: DEFAULT_MAX_BYTES)
        @max = max_events.to_i.positive? ? max_events.to_i : DEFAULT_MAX
        @events = []
        @mutex = Mutex.new
        @subscribers = [] # Each subscriber is a queue-like object responding to <<
        @subs_mutex = Mutex.new
        @file_path = file_path || default_file_path
        @max_bytes = max_bytes
        init_file_io!
      end

      # Public: Record an event Hash with standard envelope fields.
      # Fields merged:
      # - ts (UTC ISO8601)
      # - type (string)
      # - mcp (string, engine name) optional
      # - client_id (string) optional
      # Returns the final event Hash.
      def record(event)
        ev = normalize_event(event)
        line = JSON.generate(ev)

        @mutex.synchronize do
          @events << ev
          @events.shift while @events.length > @max
        end

        write_line(line)
        broadcast(ev)
        ev
      rescue StandardError
        # Swallow recorder errors to avoid impacting services
        event
      end

      # Public: Return last N events (as Hashes). Optional filter by :mcp or :type.
      def last(count = 100, mcp: nil, type: nil)
        arr = @mutex.synchronize { @events.dup }
        arr = arr.select { |e| e[:mcp].to_s == mcp.to_s } if mcp
        arr = arr.select { |e| e[:type].to_s == type.to_s } if type
        limit = [[count.to_i, 0].max, 1000].min
        arr.last(limit)
      end

      # Public: Subscribe to events. Yields an Enumerator that yields lines suitable for SSE data payloads.
      # Consumer should close the enumerator when done (on disconnect).
      def stream(mcp: nil, type: nil)
        filter = { mcp: mcp, type: type }
        queue = Queue.new
        subscribe(queue)

        Enumerator.new do |y|
          loop do
            ev = queue.pop
            next if filter[:mcp] && ev[:mcp].to_s != filter[:mcp].to_s
            next if filter[:type] && ev[:type].to_s != filter[:type].to_s

            y << JSON.generate(ev)
          end
        ensure
          unsubscribe(queue)
        end
      end

      private

      def default_file_path
        base = if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
                 ENV['SAVANT_PATH']
               else
                 File.expand_path('../../..', __dir__)
               end
        File.join(base, 'logs', 'savant.log')
      end

      def init_file_io!
        return unless @file_path

        dir = File.dirname(@file_path)
        FileUtils.mkdir_p(dir)
        @io = File.open(@file_path, 'a')
        @io.sync = true
      rescue StandardError
        @io = nil
      end

      def write_line(line)
        return unless @io

        rotate_if_needed!
        @io.puts(line)
      rescue StandardError
        # ignore file write errors
      end

      def rotate_if_needed!
        return unless @io && @max_bytes&.positive?
        return unless File.exist?(@file_path)

        size = File.size(@file_path)
        return if size < @max_bytes

        # Simple rotation: keep .0, .1, .2
        begin
          @io.close
        rescue StandardError
          # ignore
        end
        FileUtils.rm_f("#{@file_path}.2")
        FileUtils.mv("#{@file_path}.1", "#{@file_path}.2") if File.exist?("#{@file_path}.1")
        FileUtils.mv("#{@file_path}.0", "#{@file_path}.1") if File.exist?("#{@file_path}.0")
        FileUtils.mv(@file_path, "#{@file_path}.0") if File.exist?(@file_path)
        init_file_io!
      rescue StandardError
        # ignore rotation errors
      end

      def normalize_event(event)
        e = event.is_a?(Hash) ? event.dup : { message: event.to_s }
        e[:ts] ||= Time.now.utc.iso8601
        e[:type] ||= 'log'
        e
      end

      def subscribe(queue)
        @subs_mutex.synchronize { @subscribers << queue }
      end

      def unsubscribe(queue)
        @subs_mutex.synchronize { @subscribers.delete(queue) }
      end

      def broadcast(event)
        subs = @subs_mutex.synchronize { @subscribers.dup }
        subs.each do |q|
          q << event
        rescue StandardError
          # ignore
        end
      end
    end
  end
end
