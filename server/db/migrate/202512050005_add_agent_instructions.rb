class AddAgentInstructions < ActiveRecord::Migration[7.2]
  def change
    add_column :agents, :instructions, :text unless column_exists?(:agents, :instructions)
  end
end
