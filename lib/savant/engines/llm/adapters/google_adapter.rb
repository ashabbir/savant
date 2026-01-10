require_relative 'base_adapter'

module Savant::Llm::Adapters
  class GoogleAdapter < BaseAdapter
    BASE_URL = 'https://generativelanguage.googleapis.com/v1beta'

    def test_connection!
      ensure_api_key!
      uri = URI.parse("#{BASE_URL}/models?key=#{@provider[:api_key]}")
      res = http_get(uri)
      { status: 'valid', message: 'Connection successful' }
    rescue => e
      { status: 'invalid', message: e.message }
    end

    def list_models
      ensure_api_key!
      uri = URI.parse("#{BASE_URL}/models?key=#{@provider[:api_key]}")
      res = http_get(uri)
      data = JSON.parse(res.body)

      (data['models'] || []).select { |m|
        (m['supportedGenerationMethods'] || []).include?('generateContent')
      }.map { |m|
        {
          provider_model_id: m['name'].split('/').last,
          display_name: m['displayName'] || m['name'],
          modality: extract_modalities(m),
          context_window: m.dig('inputTokenLimit') || 32000,
          meta: { description: m['description'] }
        }
      }
    end

    private

    def extract_modalities(model)
      modes = []
      modes << 'text' if model['supportedGenerationMethods']&.include?('generateContent')
      modes << 'vision' if model.dig('inputCapabilities', 'images') || model['name'].include?('vision')
      modes << 'tools' if model.dig('capabilities', 'toolUse')
      modes
    end

    def ensure_api_key!
      key = @provider[:api_key].to_s.strip
      raise "Missing API key for provider #{@provider[:name]}" if key.empty?
    end
  end
end
