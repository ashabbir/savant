#!/usr/bin/env ruby
# frozen_string_literal: true

require 'socket'
require 'digest/sha1'
require 'base64'
require_relative '../../../logging/logger'
require 'fileutils'
require_relative '../../mcp/dispatcher'

module Savant
  module Transports
    module MCP
      # Low-level helpers for WebSocket HTTP handshake and framing.
      module WSProto
        module_function

        def read_http_request(socket)
          headers = {}
          request_line = socket.gets("\r\n")&.strip
          return [nil, {}] unless request_line

          while (line = socket.gets("\r\n"))
            line = line.strip
            break if line.empty?

            next unless (sep = line.index(':'))

            key = line[0...sep].downcase
            val = line[(sep + 1)..].strip
            headers[key] = val
          end
          [request_line, headers]
        end

        def write_http_response(socket, code, reason, body)
          body = body.to_s
          socket.write("HTTP/1.1 #{code} #{reason}\r\n")
          socket.write("Content-Type: text/plain\r\n")
          socket.write("Content-Length: #{body.bytesize}\r\n\r\n")
          socket.write(body)
        end

        def compute_websocket_accept(key)
          guid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
          Base64.strict_encode64(Digest::SHA1.digest(key + guid))
        end

        # Read a single, masked text frame and return payload string.
        # Returns nil if connection closed.
        def read_ws_text_frame(socket)
          h1 = socket.read(2)
          return nil unless h1 && h1.bytesize == 2

          b1, b2 = h1.bytes
          fin = b1.anybits?(0b1000_0000)
          opcode = b1 & 0b0000_1111
          masked = b2.anybits?(0b1000_0000)
          length = (b2 & 0b0111_1111)

          # Control frames: only support close immediately
          return nil if opcode == 0x8 # close
          # Only support text frames, non-fragmented
          raise 'Only text frames supported' unless opcode == 0x1 && fin
          raise 'Client frames must be masked' unless masked

          if length == 126
            ext = socket.read(2)
            raise 'Invalid extended length' unless ext && ext.bytesize == 2

            length = ext.unpack1('n')
          elsif length == 127
            ext = socket.read(8)
            raise 'Invalid extended length' unless ext && ext.bytesize == 8

            length = ext.unpack1('Q>')
          end

          mask_key = socket.read(4)
          raise 'Missing mask key' unless mask_key && mask_key.bytesize == 4

          payload = socket.read(length)
          raise 'Unexpected EOF' unless payload && payload.bytesize == length

          unmasked = xor_mask(payload, mask_key)
          unmasked.force_encoding('UTF-8')
        end

        def write_ws_text_frame(socket, data)
          bytes = data.to_s.encode('UTF-8')
          header = [0b1000_0001, 0].pack('CC') # FIN=1, opcode=1(text), no mask
          length = bytes.bytesize
          if length < 126
            header.setbyte(1, length)
            socket.write(header)
          elsif length <= 0xFFFF
            socket.write([0b1000_0001, 126, length].pack('CCn'))
          else
            socket.write([0b1000_0001, 127].pack('CC'))
            socket.write([length].pack('Q>'))
          end
          socket.write(bytes)
        end

        def xor_mask(payload, mask_key)
          mk = mask_key.bytes
          out = String.new(capacity: payload.bytesize)
          payload.bytes.each_with_index do |byte, i|
            out << (byte ^ mk[i % 4]).chr
          end
          out
        end
      end

      # Minimal WebSocket server supporting text frames for JSON-RPC 2.0.
      # - Single-frame text messages only (FIN=1, opcode=1).
      # - Client-to-server masking enforced; server responses unmasked.
      # - No TLS, no compression, optional path filtering.
      class WebSocket
        DEFAULTS = {
          host: '127.0.0.1',
          port: 8765,
          path: '/mcp',
          max_connections: 100
        }.freeze

        # rubocop:disable Metrics/ParameterLists
        def initialize(service: 'context', host: nil, port: nil, path: nil, max_connections: nil, base_path: nil)
          init_params(service: service, host: host, port: port, path: path, max_connections: max_connections,
                      base_path: base_path)
        end
        # rubocop:enable Metrics/ParameterLists

        def start
          log = prepare_logger(@service, @base_path)
          dispatcher = Savant::Framework::MCP::Dispatcher.new(service: @service, log: log)
          log.info('=' * 80)
          log.info("start: mode=websocket service=#{@service} host=#{@host} port=#{@port} path=#{@path}")
          server = TCPServer.new(@host, @port)
          log.info("listening: ws://#{@host}:#{@port}#{@path}")
          loop do
            socket = server.accept
            Thread.new(socket) do |client|
              handle_client(client, dispatcher, log)
            rescue StandardError => e
              log.error("client_error: #{e.class}: #{e.message}")
            ensure
              begin
                client.close
              rescue StandardError
                # ignore
              end
            end
          end
        rescue Interrupt
          log = Savant::Logging::Logger.new(io: $stdout, json: true, service: @service)
          log.info(event: 'shutdown', message: 'Interrupt')
        end

        private

        # rubocop:disable Metrics/ParameterLists
        def init_params(service:, host:, port:, path:, max_connections:, base_path:)
          @service = service
          cfg = DEFAULTS.dup
          cfg[:host] = host if host
          cfg[:port] = port if port
          cfg[:path] = path if path
          cfg[:max_connections] = max_connections if max_connections
          @host = cfg[:host]
          @port = Integer(cfg[:port])
          @path = cfg[:path]
          @max_connections = Integer(cfg[:max_connections])
          @base_path = base_path || default_base_path
          @connections = 0
          @connections_lock = Mutex.new
        end
        # rubocop:enable Metrics/ParameterLists

        def default_base_path
          (if ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty?
             ENV['SAVANT_PATH']
           else
             File.expand_path('../../../../..', __dir__)
           end)
        end

        def prepare_logger(service, base_path)
          log_dir = File.join(base_path, 'logs')
          FileUtils.mkdir_p(log_dir)
          log_path = File.join(log_dir, "#{service}.log")
          log_io = File.open(log_path, 'a')
          log_io.sync = true
          Savant::Logging::Logger.new(io: log_io, json: true, service: service)
        end

        def handle_client(socket, dispatcher, log)
          # Enforce connection limit
          allowed = false
          @connections_lock.synchronize do
            if @connections < @max_connections
              @connections += 1
              allowed = true
            end
          end
          unless allowed
            socket.close
            return
          end
          begin
            request_line, headers = WSProto.read_http_request(socket)
            unless request_line && headers['upgrade']&.downcase == 'websocket'
              WSProto.write_http_response(socket, 400, 'Bad Request', 'WebSocket upgrade required')
              return
            end
            # Path check
            path = request_line.split[1]
            if @path && !@path.empty? && path != @path
              WSProto.write_http_response(socket, 404, 'Not Found', 'Invalid path')
              return
            end

            key = headers['sec-websocket-key']
            if !key || key.empty?
              WSProto.write_http_response(socket, 400, 'Bad Request', 'Missing Sec-WebSocket-Key')
              return
            end
            accept = WSProto.compute_websocket_accept(key)
            socket.write("HTTP/1.1 101 Switching Protocols\r\n")
            socket.write("Upgrade: websocket\r\n")
            socket.write("Connection: Upgrade\r\n")
            socket.write("Sec-WebSocket-Accept: #{accept}\r\n")
            socket.write("Sec-WebSocket-Version: 13\r\n\r\n")
            log.info('websocket: handshake complete')

            # Message loop
            loop do
              msg = WSProto.read_ws_text_frame(socket)
              break if msg.nil?

              req, err_json = dispatcher.parse(msg)
              response_json = err_json || dispatcher.handle(req)
              WSProto.write_ws_text_frame(socket, response_json)
            end
          ensure
            @connections_lock.synchronize { @connections -= 1 }
          end
        end
      end
    end
  end
end
