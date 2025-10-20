#!/usr/bin/env ruby
#
# Purpose: Minimal Jira REST v3 client with basic auth/token support.
#
# Wraps Net::HTTP to perform JSON requests against Jira Cloud/Data Center.
# Supports email+API token and username+password auth. Does not store secrets;
# expects credentials via environment variables.

require 'json'
require 'net/http'
require 'uri'
require 'base64'
require_relative '../logger'

module Savant
  module Jira
    class Client
      def initialize(base_url:, email: nil, api_token: nil, username: nil, password: nil)
        @base_url = base_url.chomp('/'); @email=email; @api_token=api_token; @username=username; @password=password
        @log = Savant::Logger.new(component: 'jira.http')
      end

      attr_reader :base_url

      def get(path, params = {})
        http_json_request(Net::HTTP::Get, path, params: params)
      end

      def post(path, body)
        http_json_request(Net::HTTP::Post, path, body: body, json: true)
      end

      def put(path, body)
        http_json_request(Net::HTTP::Put, path, body: body, json: true)
      end

      def delete(path)
        http_json_request(Net::HTTP::Delete, path)
      end

      def multipart_post(path, raw_body, boundary)
        uri = uri_for(path)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        req = Net::HTTP::Post.new(uri.request_uri)
        req['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
        req['Accept'] = 'application/json'
        req['User-Agent'] = 'Savant-Jira-Client/1.0'
        req['X-Atlassian-Token'] = 'no-check'
        auth(req)
        req.body = raw_body
        res = http.request(req)
        unless res.is_a?(Net::HTTPSuccess)
          @log.warn("jira.http status=#{res.code} body=#{res.body&.bytesize}B")
          raise "jira request failed: #{res.code} #{res.message}"
        end
        res
      end

      def raw_get_url(url)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        req = Net::HTTP::Get.new(uri.request_uri)
        auth(req)
        res = http.request(req)
        unless res.is_a?(Net::HTTPSuccess)
          @log.warn("jira.http status=#{res.code} body=#{res.body&.bytesize}B")
          raise "jira request failed: #{res.code} #{res.message}"
        end
        res
      end

      private

      def uri_for(path)
        URI.parse("#{@base_url}#{path.start_with?('/') ? '' : '/'}#{path}")
      end

      def auth(req)
        if @api_token && @email
          token = Base64.strict_encode64("#{@email}:#{@api_token}")
          req['Authorization'] = "Basic #{token}"
        elsif @username && @password
          token = Base64.strict_encode64("#{@username}:#{@password}")
          req['Authorization'] = "Basic #{token}"
        else
          raise 'Jira credentials missing'
        end
      end

      def http_json_request(klass, path, params: nil, body: nil, json: false)
        uri = uri_for(path)
        unless params.nil? || params.empty?
          q = URI.encode_www_form(params)
          uri = URI.parse("#{uri}?#{q}")
        end
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        req = klass.new(uri.request_uri)
        req['Accept'] = 'application/json'
        req['User-Agent'] = 'Savant-Jira-Client/1.0'
        req['Content-Type'] = 'application/json' if json
        auth(req)
        req.body = body if body
        res = http.request(req)
        unless res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPNoContent)
          @log.warn("jira.http status=#{res.code} body=#{res.body&.bytesize}B")
          raise "jira request failed: #{res.code} #{res.message}"
        end
        res.body && !res.body.empty? ? JSON.parse(res.body) : {}
      end
    end
  end
end
