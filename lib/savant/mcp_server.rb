require 'json'
require 'securerandom'
require_relative 'search'
require_relative 'logger'
require_relative 'jira'

module Savant
  class MCPServer
    def initialize(host: nil, port: nil)
      settings_path = ENV['SETTINGS_PATH'] || 'config/settings.json'
      cfg = JSON.parse(File.read(settings_path)) rescue {}
      # Select MCP profile: 'context' (default) or 'jira'
      which = (ENV['MCP_SERVICE'] || 'context').to_s
      mcp_cfg = cfg.dig('mcp', which) || {}
      host ||= ENV['LISTEN_HOST'] || mcp_cfg['listenHost'] || '0.0.0.0'
      port ||= Integer(ENV['LISTEN_PORT'] || mcp_cfg['listenPort'] || (which == 'jira' ? 8766 : 8765))
      @host = host
      @port = port
    end

    def start
      log = Savant::Logger.new(component: 'mcp')
      log.info("start: host=#{@host} port=#{@port} tools=[search,jira_search]")
      # For now, accept commands on STDIN as JSON lines: {"tool":"search","q":"...","repo":null,"limit":10}
      search = Savant::Search.new
      jira = begin
        Savant::Jira.new
      rescue => e
        log.warn("jira: disabled reason=#{e.message.inspect}")
        nil
      end
      while (line = STDIN.gets)
        begin
          req = JSON.parse(line)
          rid = (req['id'] || SecureRandom.hex(6)).to_s rescue SecureRandom.hex(6)
          case req['tool']
          when 'search'
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
          when 'jira_search'
            if jira.nil?
              log.warn("jira_search: status=error id=#{rid} kind=disabled")
              puts({ ok: false, error: 'jira disabled: missing config', id: rid }.to_json)
            else
              out, exec_ms = log.with_timing { jira.search(jql: req['jql'].to_s, limit: (req['limit'] || 10).to_i, start_at: (req['start_at'] || 0).to_i) }
              log.info("write: resource=jira_search status=ok dur=#{exec_ms}ms id=#{rid} req=#{line.bytesize}B resp=#{out.to_json.bytesize}B")
              puts({ ok: true, data: out, id: rid }.to_json)
            end
          when 'jira_self'
            if jira.nil?
              log.warn("jira_self: status=error id=#{rid} kind=disabled")
              puts({ ok: false, error: 'jira disabled: missing config', id: rid }.to_json)
            else
              out, exec_ms = log.with_timing { jira.self_test }
              # For self, return the raw JSON subset
              log.info("write: resource=jira_self status=ok dur=#{exec_ms}ms id=#{rid} req=#{line.bytesize}B resp=#{out.to_json.bytesize}B")
              puts({ ok: true, data: out, id: rid }.to_json)
            end
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
