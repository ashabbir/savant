#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module Savant
  module LLM
    module Ollama
      class << self
        def host
          ENV['OLLAMA_HOST'] || 'http://127.0.0.1:11434'
        end

        # Returns { text:, usage: { prompt_tokens:, output_tokens: } }
        def generate(prompt:, model:, system: nil, json: false, max_tokens: nil, temperature: nil)
          uri = URI.parse(File.join(host, '/api/generate'))
          headers = { 'Content-Type' => 'application/json' }
          opts = {}
          opts[:temperature] = temperature if temperature
          opts[:num_predict] = max_tokens if max_tokens
          body = {
            model: model,
            prompt: prompt,
            system: system,
            options: opts,
            stream: false
          }
          body[:format] = 'json' if json

          res = http_post(uri, body: body.to_json, headers: headers)
          parsed = JSON.parse(res.body)
          text = parsed['response'] || parsed['message'] || ''
          usage = {
            prompt_tokens: parsed['prompt_eval_count'] || nil,
            output_tokens: parsed['eval_count'] || nil
          }
          { text: text.to_s, usage: usage }
        rescue Errno::ECONNREFUSED, SocketError => e
          raise StandardError, "Ollama not reachable at #{host}: #{e.message}"
        rescue JSON::ParserError => e
          raise StandardError, "Invalid response from Ollama: #{e.message}"
        end

        def models
          # Prefer current endpoint (/api/tags). Fallback to older/newer variants if needed.
          endpoints = ['/api/tags', '/api/models']
          last_error = nil

          endpoints.each do |path|
            begin
              uri = URI.parse(File.join(host, path))
              res = http_get(uri)
              parsed = JSON.parse(res.body)
              if parsed.is_a?(Array)
                return parsed
              elsif parsed.is_a?(Hash)
                arr = parsed['models'] || parsed['data']
                return (arr.is_a?(Array) ? arr : [])
              else
                return []
              end
            rescue JSON::ParserError => e
              last_error = StandardError.new("Invalid response from Ollama (#{path}): #{e.message}")
            rescue Errno::ECONNREFUSED, SocketError => e
              last_error = StandardError.new("Ollama not reachable at #{host}: #{e.message}")
            rescue StandardError => e
              last_error = e
            end
          end

          raise last_error || StandardError.new('Failed to query Ollama models')
        end

        private

        def http_post(uri, body:, headers: {})
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          req = Net::HTTP::Post.new(uri.request_uri)
          headers.each { |k, v| req[k] = v }
          req.body = body
          http.request(req)
        end

        def http_get(uri, headers: {})
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          req = Net::HTTP::Get.new(uri.request_uri)
          headers.each { |k, v| req[k] = v }
          http.request(req)
        end

        public

        # Returns list of running/loaded models (from /api/ps)
        def ps
          uri = URI.parse(File.join(host, '/api/ps'))
          res = http_get(uri)
          parsed = JSON.parse(res.body)
          return [] unless parsed.is_a?(Hash)
          arr = parsed['models'] || parsed['data'] || []
          arr.is_a?(Array) ? arr : []
        rescue Errno::ECONNREFUSED, SocketError => e
          raise StandardError, "Ollama not reachable at #{host}: #{e.message}"
        rescue JSON::ParserError => e
          raise StandardError, "Invalid response from Ollama: #{e.message}"
        end
      end
    end
  end
end
