# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'
require 'securerandom'
require 'thread'
require 'timeout'

module Savant
  class Multiplexer
    class EngineProcess
      class RPCError < StandardError; end
      class TimeoutError < StandardError; end
      class OfflineError < StandardError; end

      attr_reader :name, :status, :pid, :started_at, :last_error, :last_heartbeat, :tools

      def initialize(name:, base_path:, command: nil, env: {}, logger:, on_status_change: nil)
        @name = name
        @base_path = base_path
        @command = command || default_command
        @env = env || {}
        @logger = logger
        @on_status_change = on_status_change
        @status = :idle
        @pending = {}
        @pending_lock = Mutex.new
        @tools = []
      end

      def start!
        return if running?

        env = default_env.merge(@env.transform_keys(&:to_s))
        @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(env, *@command, chdir: @base_path)
        @pid = @wait_thr.pid
        @status = :booting
        @started_at = Time.now
        @last_error = nil
        @stdout_thread = Thread.new { stdout_loop }
        @stderr_thread = Thread.new { stderr_loop }
        @waiter_thread = Thread.new { process_wait_loop }

        begin
          rpc_call('initialize', {})
          refresh_tools!
          update_status(:online)
        rescue StandardError => e
          update_status(:offline, e.message)
          raise
        end
        true
      end

      def stop!
        return unless @stdin

        begin
          @stdin.close unless @stdin.closed?
        rescue StandardError
          # ignore
        end
        [@stdout, @stderr].each do |io|
          begin
            io.close unless io.closed?
          rescue StandardError
            # ignore
          end
        end
        if @wait_thr&.alive?
          begin
            Process.kill('TERM', @wait_thr.pid)
          rescue StandardError
            # ignore
          end
        end
        @stdin = @stdout = @stderr = nil
        @wait_thr = nil
        [@stdout_thread, @stderr_thread, @waiter_thread].each do |thr|
          thr&.kill
        rescue StandardError
          # ignore
        end
        @stdout_thread = @stderr_thread = @waiter_thread = nil
        update_status(:offline)
      end

      def restart!
        stop!
        start!
      end

      def online?
        @status == :online
      end

      def running?
        @wait_thr && @wait_thr.alive?
      end

      def refresh_tools!
        resp = rpc_call('tools/list', {})
        list = resp.dig('result', 'tools') || []
        @tools = list
      end

      def call_tool(tool, args)
        raise OfflineError, "#{name} offline" unless running?

        payload = { 'name' => tool, 'arguments' => args || {} }
        resp = rpc_call('tools/call', payload)
        if resp['error']
          raise RPCError, resp['error']['message']
        end

        resp['result']
      end

      def snapshot
        {
          name: name,
          status: status,
          pid: pid,
          started_at: started_at,
          uptime_seconds: started_at ? (Time.now - started_at).to_i : 0,
          last_error: last_error,
          last_heartbeat: last_heartbeat,
          tools: tools.size
        }
      end

      private

      def default_command
        [RbConfig.ruby, File.join(@base_path, 'bin', 'mcp_server'), '--transport=stdio']
      end

      def default_env
        env = ENV.to_h.dup
        env['MCP_SERVICE'] = @name
        env['SAVANT_PATH'] = @base_path
        env
      end

      def stdout_loop
        while (line = @stdout.gets)
          line = line.strip
          next if line.empty?
          handle_response(line)
        end
      rescue StandardError => e
        @logger.warn(event: 'engine_stdout_error', engine: name, error: e.message)
      ensure
        update_status(:offline, 'stdout closed') unless @status == :offline
      end

      def stderr_loop
        while (line = @stderr.gets)
          @logger.warn(event: 'engine_stderr', engine: name, line: line.strip)
        end
      rescue StandardError
        # ignore
      end

      def process_wait_loop
        return unless @wait_thr

        @wait_thr.value
        update_status(:offline, 'process exited')
      rescue StandardError => e
        update_status(:offline, e.message)
      end

      def handle_response(line)
        data = JSON.parse(line)
        id = data['id']
        return unless id

        @pending_lock.synchronize do
          waiter = @pending.delete(id)
          waiter << data if waiter
        end
      rescue JSON::ParserError => e
        @logger.error(event: 'engine_parse_error', engine: name, line: line[0..120], error: e.message)
      end

      def rpc_call(method, params)
        raise OfflineError, "#{name} offline" unless running?

        id = SecureRandom.uuid
        req = { jsonrpc: '2.0', id: id, method: method, params: params }
        q = Queue.new
        @pending_lock.synchronize { @pending[id] = q }
        @stdin.puts(JSON.generate(req))
        @stdin.flush
        Timeout.timeout(30) { q.pop }
      rescue Timeout::Error
        @pending_lock.synchronize { @pending.delete(id) }
        raise TimeoutError, "#{name} RPC timeout"
      rescue IOError => e
        raise OfflineError, e.message
      end

      def update_status(new_status, error_message = nil)
        return if @status == new_status && error_message.nil?

        @status = new_status
        @last_error = error_message if error_message
        @last_heartbeat = Time.now
        @on_status_change&.call(self, new_status, error_message)
      end
    end
  end
end
