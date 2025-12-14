class AddModelIdToAgents < ActiveRecord::Migration[7.2]
  def change
    add_column :agents, :model_id, :integer
    add_foreign_key :agents, :llm_models, column: :model_id, on_delete: :nullify
  end
end
