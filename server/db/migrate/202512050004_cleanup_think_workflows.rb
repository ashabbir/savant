class CleanupThinkWorkflows < ActiveRecord::Migration[7.2]
  def change
    remove_column :think_workflows, :driver_version, :text if column_exists?(:think_workflows, :driver_version)
    remove_column :think_workflows, :rules, :text if column_exists?(:think_workflows, :rules)
  end
end
