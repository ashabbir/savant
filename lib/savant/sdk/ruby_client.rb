#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

module Savant
  module SDK
    # Minimal JSON-RPC client for Savant HTTP endpoints.
    # Transport is pluggable: provide a block that performs HTTP POST.
    class RubyClient
      def initialize(url:, &transport)
        @url = url
        @transport = transport || method(:default_transport)
      end

      # List tools via JSON-RPC tools/list
      def list_tools
        rpc('tools/list', params: {})
      end

      # Call a tool by name with arguments
      def call_tool(name, arguments = {})
        rpc('tools/call', params: { name: name, arguments: arguments })
      end

      private

      def rpc(method, params: {})
        req = { jsonrpc: '2.0', id: next_id, method: method, params: params }
        body = JSON.generate(req)
        res_body = @transport.call(@url, body)
        JSON.parse(res_body)
      end

      def next_id
        (@_id ||= 0)
        @_id += 1
      end

      def default_transport(url, body)
        require 'net/http'
        require 'uri'
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        req = Net::HTTP::Post.new(uri.request_uri)
        req['content-type'] = 'application/json'
        req.body = body
        res = http.request(req)
        res.body
      end
    end
  end
end

