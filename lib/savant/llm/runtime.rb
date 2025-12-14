require 'savant/llm/registry'

module Savant::LLM
  class Runtime
    def self.for_agent(agent_name)
      registry = Registry.new
      agents = registry.list_agents
      agent = agents.find { |a| a[:name] == agent_name }

      return nil unless agent && agent[:model_id]

      models = registry.list_models
      model = models.find { |m| m[:id] == agent[:model_id].to_i }
      return nil unless model

      provider = registry.get_provider(model[:provider_name])
      return nil unless provider

      {
        provider: provider,
        model: model,
        credentials: { api_key: provider[:api_key], base_url: provider[:base_url] }
      }
    end
  end
end
