require 'json'

module Savant
  class MCPServer
    def initialize(host: ENV['LISTEN_HOST'] || '0.0.0.0', port: Integer(ENV['LISTEN_PORT'] || 8765))
      @host = host
      @port = port
    end

    def start
      # Placeholder: real implementation will use async-websocket
      puts "READY mcp listening host=#{@host} port=#{@port} tools=[search]"
      sleep
    rescue Interrupt
      puts 'MCP SHUTDOWN'
    end
  end
end

