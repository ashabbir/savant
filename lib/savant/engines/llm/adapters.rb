require_relative 'adapters/google_adapter'
require_relative 'adapters/ollama_adapter'

module Savant::Llm::Adapters
  def self.for_provider(provider_row)
    case provider_row[:provider_type]
    when 'google' then GoogleAdapter.new(provider_row)
    when 'ollama' then OllamaAdapter.new(provider_row)
    else raise "Unsupported provider type: #{provider_row[:provider_type]}"
    end
  end
end
