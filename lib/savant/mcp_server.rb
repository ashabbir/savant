require 'json'
require 'securerandom'
require_relative 'search'
require_relative 'logger'

module Savant
  class MCPServer
    def initialize(host: ENV['LISTEN_HOST'] || '0.0.0.0', port: Integer(ENV['LISTEN_PORT'] || 8765))
      @host = host
      @port = port
    end

    def start
      log = Savant::Logger.new(component: 'mcp')
      log.info("start: host=#{@host} port=#{@port} tools=[search]")
      # For now, accept commands on STDIN as JSON lines: {"tool":"search","q":"...","repo":null,"limit":10}
      search = Savant::Search.new
      while (line = STDIN.gets)
        begin
          req = JSON.parse(line)
          rid = (req['id'] || SecureRandom.hex(6)).to_s rescue SecureRandom.hex(6)
          if req['tool'] == 'search'
            _, dur = log.with_timing(label: "read: resource=search id=#{rid}") do
              # timing wrapper only
            end
            out, exec_ms = nil, nil
            out, exec_ms = begin
              r, d = log.with_timing { search.search(q: req['q'].to_s, repo: req['repo'], limit: (req['limit'] || 10).to_i) }
              [r, d]
            end
            log.info("write: resource=search status=ok dur=#{exec_ms}ms id=#{rid} req=#{line.bytesize}B resp=#{out.to_json.bytesize}B")
            puts({ ok: true, data: out, id: rid }.to_json)
          else
            log.warn("read: resource=#{req['tool']} status=error id=#{rid} kind=unknown_tool")
            puts({ ok: false, error: 'unknown tool', id: rid }.to_json)
          end
        rescue => e
          log.error("write: resource=unknown status=error id=? kind=#{e.class} msg=#{e.message}")
          puts({ ok: false, error: e.message }.to_json)
        end
      end
    rescue Interrupt
      log = Savant::Logger.new(component: 'mcp')
      log.info('shutdown')
    end
  end
end
