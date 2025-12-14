require 'net/http'
require 'uri'
require 'json'

module Savant::Llm::Adapters
  class BaseAdapter
    def initialize(provider_row)
      @provider = provider_row
      @log = Savant::Logging::MongoLogger.new(service: 'llm.adapter')
    end

    def test_connection!
      raise NotImplementedError
    end

    def list_models
      raise NotImplementedError
    end

    protected

    def http_get(uri, headers: {})
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 5
      http.read_timeout = 10

      req = Net::HTTP::Get.new(uri.request_uri)
      headers.each { |k, v| req[k] = v }

      res = http.request(req)
      unless res.is_a?(Net::HTTPSuccess)
        raise "HTTP #{res.code}: #{res.body}"
      end

      res
    end
  end
end
