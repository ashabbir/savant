require 'json'
require_relative 'search'

module Savant
  class MCPServer
    def initialize(host: ENV['LISTEN_HOST'] || '0.0.0.0', port: Integer(ENV['LISTEN_PORT'] || 8765))
      @host = host
      @port = port
    end

    def start
      # Placeholder: real implementation will use async-websocket
      puts "READY mcp listening host=#{@host} port=#{@port} tools=[search]"
      # For now, accept commands on STDIN as JSON lines: {"tool":"search","q":"...","repo":null,"limit":10}
      search = Savant::Search.new
      while (line = STDIN.gets)
        begin
          req = JSON.parse(line)
          if req['tool'] == 'search'
            out = search.search(q: req['q'].to_s, repo: req['repo'], limit: (req['limit'] || 10).to_i)
            puts({ ok: true, data: out }.to_json)
          else
            puts({ ok: false, error: 'unknown tool' }.to_json)
          end
        rescue => e
          puts({ ok: false, error: e.message }.to_json)
        end
      end
    rescue Interrupt
      puts 'MCP SHUTDOWN'
    end
  end
end
