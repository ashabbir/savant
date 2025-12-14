require 'savant/engines/llm/adapters/base_adapter'

module Savant::LLM::Adapters
  class OllamaAdapter < BaseAdapter
    def test_connection!
      uri = URI.parse("#{@provider[:base_url]}/api/tags")
      res = http_get(uri)
      { status: 'valid', message: 'Connection successful' }
    rescue => e
      { status: 'invalid', message: e.message }
    end

    def list_models
      uri = URI.parse("#{@provider[:base_url]}/api/tags")
      res = http_get(uri)
      data = JSON.parse(res.body)

      (data['models'] || []).map { |m|
        {
          provider_model_id: m['name'],
          display_name: m['name'],
          modality: ['text'],
          context_window: m.dig('details', 'parameter_size') ? 8192 : 4096,
          meta: { size: m['size'], modified_at: m['modified_at'] }
        }
      }
    end
  end
end
