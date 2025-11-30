#!/usr/bin/env ruby
# frozen_string_literal: true

require 'time'
require 'securerandom'
require_relative '../logging/event_recorder'

module Savant
  module Hub
    # Global connection registry for SSE/HTTP/STDIO clients.
    # Tracks: id, type, mcp, path, user_id, connected_at, last_activity
    class Connections
    def self.global
      @global ||= new
    end

    def initialize
      @conns = {}
      @mutex = Mutex.new
    end

    def connect(type:, mcp: nil, path: nil, user_id: nil)
      id = gen_id(type)
      now = Time.now.utc.iso8601
      rec = { id: id, type: type, mcp: mcp, path: path, user_id: user_id, connected_at: now, last_activity: now }
      @mutex.synchronize { @conns[id] = rec }
      Savant::Logging::EventRecorder.global.record(type: 'client_connected', mcp: mcp, client_id: id, conn_type: type, path: path, user_id: user_id)
      id
    end

    def touch(id)
      @mutex.synchronize do
        rec = @conns[id]
        rec[:last_activity] = Time.now.utc.iso8601 if rec
      end
    end

    def disconnect(id)
      rec = @mutex.synchronize { @conns.delete(id) }
      return unless rec

      Savant::Logging::EventRecorder.global.record(type: 'client_disconnected', mcp: rec[:mcp], client_id: id, conn_type: rec[:type], path: rec[:path])
    end

    def list(type: nil, mcp: nil)
      arr = @mutex.synchronize { @conns.values.map(&:dup) }
      arr = arr.select { |c| c[:type].to_s == type.to_s } if type
      arr = arr.select { |c| c[:mcp].to_s == mcp.to_s } if mcp
      arr
    end

    private

    def gen_id(type)
      "#{type}-#{SecureRandom.hex(6)}"
      end
    end
  end
end
