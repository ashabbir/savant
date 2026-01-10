require_relative '../../framework/mcp/core/dsl'
require_relative 'engine'

module Savant::Llm::Tools
  module_function

  # Return the MCP tool specs for the LLM service
  def specs
    build_registrar.specs
  end

  # Dispatch a tool call by name to the LLM engine
  def dispatch(engine, name, args)
    reg = build_registrar(engine)
    base_ctx = { engine: engine, service: 'llm' }
    base_ctx[:logger] = engine&.logger
    reg.call(name, args || {}, ctx: base_ctx)
  end

  def build_registrar(engine = nil)
    Savant::Framework::MCP::Core::DSL.build do
      # Provider tools
      tool 'llm_providers_list', description: 'List all LLM providers',
           schema: { type: 'object', properties: {} } do |_ctx, _a|
        engine.provider_list
      end

      tool 'llm_providers_create', description: 'Create a new LLM provider',
           schema: {
             type: 'object',
             properties: {
               name: { type: 'string' },
               provider_type: { type: 'string', enum: ['google', 'ollama'] },
               base_url: { type: 'string' },
               api_key: { type: 'string' }
             },
             required: ['name', 'provider_type']
           } do |_ctx, a|
        engine.provider_create(
          name: a['name'],
          provider_type: a['provider_type'],
          base_url: a['base_url'],
          api_key: a['api_key']
        )
      end

      tool 'llm_providers_test', description: 'Test provider connection',
           schema: {
             type: 'object',
             properties: { name: { type: 'string' } },
             required: ['name']
           } do |_ctx, a|
        engine.provider_test(name: a['name'])
      end

      tool 'llm_providers_update', description: 'Update provider settings',
           schema: {
             type: 'object',
             properties: {
               name: { type: 'string' },
               base_url: { type: 'string' },
               api_key: { type: 'string' }
             },
             required: ['name']
           } do |_ctx, a|
        engine.provider_update(
          name: a['name'],
          base_url: a['base_url'],
          api_key: a['api_key']
        )
      end

      tool 'llm_providers_read', description: 'Read provider details (includes api_key)',
           schema: {
             type: 'object',
             properties: { name: { type: 'string' } },
             required: ['name']
           } do |_ctx, a|
        engine.provider_read(name: a['name'])
      end

      tool 'llm_providers_delete', description: 'Delete a provider',
           schema: {
             type: 'object',
             properties: { name: { type: 'string' } },
             required: ['name']
           } do |_ctx, a|
        engine.provider_delete(name: a['name'])
      end

      # Model tools
      tool 'llm_models_discover', description: 'Discover available models from provider',
           schema: {
             type: 'object',
             properties: { provider_name: { type: 'string' } },
             required: ['provider_name']
           } do |_ctx, a|
        engine.models_discover(provider_name: a['provider_name'])
      end

      tool 'llm_models_register', description: 'Register selected models',
           schema: {
             type: 'object',
             properties: {
               provider_name: { type: 'string' },
               model_ids: { type: 'array', items: { type: 'string' } }
             },
             required: ['provider_name', 'model_ids']
           } do |_ctx, a|
       engine.models_register(
         provider_name: a['provider_name'],
         model_ids: a['model_ids']
       )
      end

      tool 'llm_models_update', description: 'Update registered model metadata',
           schema: {
             type: 'object',
             properties: {
               model_id: { type: 'integer' },
               display_name: { type: 'string' },
               context_window: { type: 'integer' },
               modality: { type: 'array', items: { type: 'string' } },
               enabled: { type: 'boolean' }
             },
             required: ['model_id']
           } do |_ctx, a|
        engine.models_update(
          model_id: a['model_id'],
          display_name: a['display_name'],
          context_window: a['context_window'],
          modality: a['modality'],
          enabled: a['enabled']
        )
      end

      tool 'llm_models_list', description: 'List registered models',
           schema: { type: 'object', properties: {} } do |_ctx, _a|
        engine.models_list
      end

      tool 'llm_models_delete', description: 'Delete a registered model',
           schema: {
             type: 'object',
             properties: { model_id: { type: 'integer' } },
             required: ['model_id']
           } do |_ctx, a|
        engine.models_delete(model_id: a['model_id'])
      end

      tool 'llm_models_set_enabled', description: 'Enable or disable a model',
           schema: {
             type: 'object',
             properties: {
               model_id: { type: 'integer' },
               enabled: { type: 'boolean' }
             },
             required: ['model_id', 'enabled']
           } do |_ctx, a|
        engine.models_set_enabled(model_id: a['model_id'], enabled: a['enabled'])
      end

      # Agent tools
      tool 'llm_agents_create', description: 'Create an agent',
           schema: {
             type: 'object',
             properties: {
               name: { type: 'string' },
               description: { type: 'string' }
             },
             required: ['name']
           } do |_ctx, a|
        engine.agent_create(name: a['name'], description: a['description'])
      end

      tool 'llm_agents_list', description: 'List agents',
           schema: { type: 'object', properties: {} } do |_ctx, _a|
        engine.agent_list
      end

      tool 'llm_agents_delete', description: 'Delete an agent',
           schema: {
             type: 'object',
             properties: { name: { type: 'string' } },
             required: ['name']
           } do |_ctx, a|
        engine.agent_delete(name: a['name'])
      end

      tool 'llm_agents_assign_model', description: 'Assign model to agent',
           schema: {
             type: 'object',
             properties: {
               agent_name: { type: 'string' },
               model_id: { type: 'integer' }
             },
             required: ['agent_name', 'model_id']
           } do |_ctx, a|
        engine.agent_assign_model(
          agent_name: a['agent_name'],
          model_id: a['model_id']
        )
      end
    end
  end
end
