class AddAllowedToolsToAgents < ActiveRecord::Migration[7.1]
  def change
    add_column :agents, :allowed_tools, :text, array: true unless column_exists?(:agents, :allowed_tools)
  end
end
