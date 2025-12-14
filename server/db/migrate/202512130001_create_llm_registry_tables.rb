class CreateLlmRegistryTables < ActiveRecord::Migration[7.2]
  def change
    create_table :llm_providers do |t|
      t.text :name, null: false
      t.text :provider_type, null: false
      t.text :base_url
      t.binary :encrypted_api_key
      t.binary :api_key_nonce
      t.binary :api_key_tag
      t.text :status, default: 'unknown'
      t.timestamptz :last_validated_at
      t.timestamps default: -> { 'NOW()' }
    end
    add_index :llm_providers, :name, unique: true

    create_table :llm_models do |t|
      t.references :provider, null: false, foreign_key: { to_table: :llm_providers, on_delete: :cascade }
      t.text :provider_model_id, null: false
      t.text :display_name, null: false
      t.text :modality, array: true, default: []
      t.integer :context_window
      t.numeric :input_cost_per_1k
      t.numeric :output_cost_per_1k
      t.boolean :enabled, default: true
      t.jsonb :meta, default: {}
      t.timestamps default: -> { 'NOW()' }
    end
    add_index :llm_models, [:provider_id, :provider_model_id], unique: true

    create_table :llm_agents do |t|
      t.text :name, null: false
      t.text :description
      t.timestamps default: -> { 'NOW()' }
    end
    add_index :llm_agents, :name, unique: true

    create_table :llm_agent_model_assignments, id: false do |t|
      t.references :agent, null: false, foreign_key: { to_table: :llm_agents, on_delete: :cascade }
      t.references :model, null: false, foreign_key: { to_table: :llm_models, on_delete: :cascade }
    end
    add_index :llm_agent_model_assignments, :agent_id, unique: true

    create_table :llm_cache do |t|
      t.references :provider, null: false, foreign_key: { to_table: :llm_providers, on_delete: :cascade }
      t.text :key, null: false
      t.jsonb :value
      t.timestamptz :expires_at, null: false
    end
    add_index :llm_cache, [:provider_id, :key], unique: true
  end
end
