require_relative '../../framework/engine/engine'
require_relative 'registry'
require_relative 'adapters'

module Savant::Llm
  class Engine < Savant::Framework::Engine::Base
    def initialize
      super()
      @logger = Savant::Logging::MongoLogger.new(service: 'llm.engine')
      @registry = Registry.new
    end

    def server_info
      { name: 'savant-llm', version: Savant::VERSION, description: 'LLM Model Registry' }
    end

    # Provider operations
    def provider_create(name:, provider_type:, base_url: nil, api_key: nil)
      @registry.create_provider(name: name, provider_type: provider_type, base_url: base_url, api_key: api_key)
      { ok: true, name: name }
    end

    def provider_list
      { providers: @registry.list_providers }
    end

    def provider_test(name:)
      provider = @registry.get_provider(name)
      raise "Provider not found: #{name}" unless provider

      adapter = Savant::Llm::Adapters.for_provider(provider)
      result = adapter.test_connection!

      @registry.update_provider_status(name, result[:status])
      result
    end

    def provider_delete(name:)
      @registry.delete_provider(name)
      { ok: true, deleted: true }
    end

    def provider_update(name:, base_url: nil, api_key: nil)
      @registry.update_provider(name: name, base_url: base_url, api_key: api_key)
    end

    # Model operations
    def models_discover(provider_name:)
      provider = @registry.get_provider(provider_name)
      raise "Provider not found: #{provider_name}" unless provider

      adapter = Savant::Llm::Adapters.for_provider(provider)
      models = adapter.list_models
      { models: models }
    end

    def models_register(provider_name:, model_ids:)
      provider = @registry.get_provider(provider_name)
      raise "Provider not found: #{provider_name}" unless provider

      adapter = Savant::Llm::Adapters.for_provider(provider)
      available = adapter.list_models

      registered = []
      model_ids.each do |mid|
        model = available.find { |m| m[:provider_model_id] == mid }
        next unless model

        id = @registry.register_model(
        provider_id: provider[:id],
        provider_model_id: model[:provider_model_id],
        display_name: model[:display_name],
        modality: model[:modality],
        context_window: model[:context_window],
        meta: model[:meta]
      )
        registered << id
      end

      { ok: true, registered: registered.length }
    end

    def models_list
      { models: @registry.list_models }
    end

    def models_delete(model_id:)
      @registry.delete_model(model_id)
      { ok: true, deleted: true }
    end

    def models_set_enabled(model_id:, enabled:)
      @registry.enable_model(model_id, enabled)
      { ok: true }
    end

    # Agent operations
    def agent_create(name:, description: nil)
      @registry.create_agent(name: name, description: description)
      { ok: true, name: name }
    end

    def agent_list
      { agents: @registry.list_agents }
    end

    def agent_delete(name:)
      @registry.delete_agent(name)
      { ok: true, deleted: true }
    end

    def agent_assign_model(agent_name:, model_id:)
      # Update the Rails agents table instead of using the separate llm_agents table
      require 'savant/framework/db'
      db = Savant::Framework::DB.new
      db.exec_params(
        'UPDATE agents SET model_id = $1 WHERE name = $2',
        [model_id, agent_name]
      )
      { ok: true }
    end
  end
end
