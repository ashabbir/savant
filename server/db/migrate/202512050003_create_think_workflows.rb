class CreateThinkWorkflows < ActiveRecord::Migration[7.2]
  def change
    create_table :think_workflows do |t|
      t.text :workflow_id, null: false
      t.text :name
      t.text :description
      t.integer :version, null: false, default: 1
      t.jsonb :steps, null: false, default: {}
      t.timestamps default: -> { 'NOW()' }, null: false
    end
    add_index :think_workflows, :workflow_id, unique: true
  end
end
