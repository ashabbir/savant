require 'savant/engines/llm/vault'

module Savant::Llm
  class Registry
    def initialize(db = nil)
      @db = db || Savant::Framework::DB.new
    end

    # Provider CRUD
    def create_provider(name:, provider_type:, base_url: nil, api_key: nil)
      encrypted = nil
      nonce = nil
      tag = nil
      if api_key
        enc_result = Vault.encrypt(api_key)
        encrypted = enc_result[:ciphertext]
        nonce = enc_result[:nonce]
        tag = enc_result[:tag]
      end

      @db.exec_params(
        <<~SQL,
          INSERT INTO llm_providers (name, provider_type, base_url, encrypted_api_key, api_key_nonce, api_key_tag)
          VALUES ($1, $2, $3, $4, $5, $6)
          RETURNING id
        SQL
        [name, provider_type, base_url, encrypted&.unpack1('H*'), nonce&.unpack1('H*'), tag&.unpack1('H*')]
      )[0]['id']
    end

    def list_providers
      res = @db.exec_params('SELECT id, name, provider_type, base_url, status, last_validated_at FROM llm_providers ORDER BY name', [])
      res.map { |row| row.transform_keys(&:to_sym) }
    end

    def get_provider(name)
      res = @db.exec_params('SELECT * FROM llm_providers WHERE name = $1', [name])
      return nil if res.ntuples.zero?

      row = res[0]
      decrypt_provider_row(row)
    end

    def delete_provider(name)
      @db.exec_params('DELETE FROM llm_providers WHERE name = $1', [name])
    end

    def update_provider_status(name, status, validated_at = Time.now)
      @db.exec_params(
        'UPDATE llm_providers SET status = $1, last_validated_at = $2 WHERE name = $3',
        [status, validated_at, name]
      )
    end

    # Model CRUD
    def register_model(provider_id:, provider_model_id:, display_name:, modality: [], context_window: nil, meta: {})
      modality_encoded = text_array_encoder.encode(Array(modality))
      @db.exec_params(
        <<~SQL,
          INSERT INTO llm_models (provider_id, provider_model_id, display_name, modality, context_window, meta)
          VALUES ($1, $2, $3, $4, $5, $6)
          ON CONFLICT (provider_id, provider_model_id) DO UPDATE
          SET display_name = EXCLUDED.display_name, modality = EXCLUDED.modality, context_window = EXCLUDED.context_window, meta = EXCLUDED.meta
          RETURNING id
        SQL
        [provider_id, provider_model_id, display_name, modality_encoded, context_window, meta.to_json]
      )[0]['id']
    end

    def list_models(provider_id: nil, enabled: nil)
      sql = 'SELECT m.*, p.name as provider_name, p.provider_type FROM llm_models m JOIN llm_providers p ON m.provider_id = p.id WHERE 1=1'
      params = []
      if provider_id
        sql += ' AND m.provider_id = $1'
        params << provider_id
      end
      if !enabled.nil?
        sql += " AND m.enabled = $#{params.length + 1}"
        params << enabled
      end
      sql += ' ORDER BY p.name, m.display_name'

      res = @db.exec_params(sql, params)
      res.map { |row| row.transform_keys(&:to_sym) }
    end

    def enable_model(model_id, enabled)
      @db.exec_params('UPDATE llm_models SET enabled = $1 WHERE id = $2', [enabled, model_id])
    end

    def delete_model(model_id)
      @db.exec_params('DELETE FROM llm_models WHERE id = $1', [model_id])
    end

    # Agent CRUD
    def create_agent(name:, description: nil)
      @db.exec_params(
        'INSERT INTO llm_agents (name, description) VALUES ($1, $2) RETURNING id',
        [name, description]
      )[0]['id']
    end

    def list_agents
      res = @db.exec_params(
        <<~SQL,
          SELECT a.*, m.display_name as model_name, m.id as model_id
          FROM llm_agents a
          LEFT JOIN llm_agent_model_assignments ama ON a.id = ama.agent_id
          LEFT JOIN llm_models m ON ama.model_id = m.id
          ORDER BY a.name
        SQL
        []
      )
      res.map { |row| row.transform_keys(&:to_sym) }
    end

    def delete_agent(name)
      @db.exec_params('DELETE FROM llm_agents WHERE name = $1', [name])
    end

    # Agent model assignment
    def assign_model(agent_name:, model_id:)
      agent = @db.exec_params('SELECT id FROM llm_agents WHERE name = $1', [agent_name])[0]
      raise "Agent not found: #{agent_name}" unless agent

      @db.exec_params(
        <<~SQL,
          INSERT INTO llm_agent_model_assignments (agent_id, model_id)
          VALUES ($1, $2)
          ON CONFLICT (agent_id) DO UPDATE SET model_id = EXCLUDED.model_id
        SQL
        [agent['id'], model_id]
      )
    end

    private

    def text_array_encoder
      @text_array_encoder ||= PG::TextEncoder::Array.new(
        name: 'text[]',
        elements_type: PG::TextEncoder::String.new(name: 'text')
      )
    end

    def decrypt_provider_row(row)
      result = row.transform_keys(&:to_sym)
      if row['encrypted_api_key'] && row['api_key_nonce'] && row['api_key_tag']
        ciphertext = [row['encrypted_api_key']].pack('H*')
        nonce = [row['api_key_nonce']].pack('H*')
        tag = [row['api_key_tag']].pack('H*')
        result[:api_key] = Vault.decrypt(ciphertext, nonce, tag)
      end
      result.delete(:encrypted_api_key)
      result.delete(:api_key_nonce)
      result.delete(:api_key_tag)
      result
    end
  end
end
