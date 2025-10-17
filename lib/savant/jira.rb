require 'json'
require 'net/http'
require 'uri'
require 'base64'
require_relative 'logger'

module Savant
  class Jira
    DEFAULT_FIELDS = %w[key summary status assignee updated].freeze

    def initialize(base_url: ENV['JIRA_BASE_URL'], email: ENV['JIRA_EMAIL'], api_token: ENV['JIRA_API_TOKEN'], username: ENV['JIRA_USERNAME'], password: ENV['JIRA_PASSWORD'], fields: (ENV['JIRA_FIELDS']&.split(',')&.map(&:strip) || DEFAULT_FIELDS))
      # Prefer settings.json (via Savant::Config) if available
      cfg = nil
      begin
        if ENV['SETTINGS_PATH'] && File.file?(ENV['SETTINGS_PATH'])
          all = JSON.parse(File.read(ENV['SETTINGS_PATH'])) rescue nil
          cfg = all && (all['jira'] || all['Jira'])
        end
      rescue => e
        Savant::Logger.new(component: 'jira').warn("jira.config settings_load_failed kind=#{e.class} msg=#{e.message}")
        cfg = nil
      end
      base_url = (cfg && (cfg['baseUrl'] || cfg['base_url'])) || base_url
      email    = (cfg && cfg['email']) || email
      api_token = (cfg && (cfg['apiToken'] || cfg['api_token'])) || api_token
      username = (cfg && cfg['username']) || username
      password = (cfg && cfg['password']) || password
      fields   = (cfg && (cfg['fields'] || cfg['Fields'])) || fields

      @base_url = base_url&.chomp('/')
      @email = email
      @api_token = api_token
      @username = username
      @password = password
      @fields = fields
      @log = Savant::Logger.new(component: 'jira')
      raise 'JIRA_BASE_URL is required' unless @base_url
    end

    def search(jql:, limit: 10, start_at: 0)
      raise 'jql is required' if jql.to_s.strip.empty?
      uri = URI.parse("#{@base_url}/rest/api/3/search")
      body = { jql: jql, maxResults: limit.to_i, startAt: start_at.to_i, fields: @fields }.to_json
      _resp, ms = @log.with_timing(label: 'jira.search') do
        http_post(uri, body)
      end
    end

    def self_test
      uri = URI.parse("#{@base_url}/rest/api/3/myself")
      _resp, ms = @log.with_timing(label: 'jira.self') do
        http_get(uri, {})
      end
    end

    private

    def http_post(uri, body)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      req = Net::HTTP::Post.new(uri.request_uri)
      req['Content-Type'] = 'application/json'
      req['Accept'] = 'application/json'
      req['User-Agent'] = 'Savant-Jira-Client/1.0'
      req['Atlassian-Token'] = 'no-check'
      auth(req)
      req.body = body
      res = http.request(req)
      unless res.is_a?(Net::HTTPSuccess)
        @log.warn("jira.http status=#{res.code} body=#{res.body&.bytesize}B")
        raise "jira request failed: #{res.code} #{res.message}"
      end
      json = JSON.parse(res.body)
      map_issues(json)
    end

    def http_get(uri, params)
      q = URI.encode_www_form(params)
      full = q.nil? || q.empty? ? uri : URI.parse("#{uri}?#{q}")
      http = Net::HTTP.new(full.host, full.port)
      http.use_ssl = full.scheme == 'https'
      req = Net::HTTP::Get.new(full.request_uri)
      req['Accept'] = 'application/json'
      req['User-Agent'] = 'Savant-Jira-Client/1.0'
      auth(req)
      res = http.request(req)
      unless res.is_a?(Net::HTTPSuccess)
        @log.warn("jira.http status=#{res.code} body=#{res.body&.bytesize}B")
        raise "jira request failed: #{res.code} #{res.message}"
      end
      json = JSON.parse(res.body)
      map_issues(json)
    end

    def auth(req)
      if @api_token && @email
        token = Base64.strict_encode64("#{@email}:#{@api_token}")
        req['Authorization'] = "Basic #{token}"
      elsif @username && @password
        token = Base64.strict_encode64("#{@username}:#{@password}")
        req['Authorization'] = "Basic #{token}"
      else
        raise 'Jira credentials missing: set JIRA_EMAIL+JIRA_API_TOKEN or JIRA_USERNAME+JIRA_PASSWORD'
      end
    end

    def map_issues(json)
      (json['issues'] || []).map do |it|
        f = it['fields'] || {}
        {
          key: it['key'],
          summary: f.dig('summary'),
          status: f.dig('status', 'name'),
          assignee: f.dig('assignee', 'displayName'),
          updated: f['updated'],
          url: "#{@base_url}/browse/#{it['key']}"
        }
      end
    end
  end
end
