class AddDriverNameToAgents < ActiveRecord::Migration[7.1]
  def up
    unless column_exists?(:agents, :driver_name)
      add_column :agents, :driver_name, :text
    end
  end

  def down
    if column_exists?(:agents, :driver_name)
      remove_column :agents, :driver_name
    end
  end
end

