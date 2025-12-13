class ExtendPersonasRulesetsAddDrivers < ActiveRecord::Migration[7.2]
  def change
    change_table :personas do |t|
      t.integer :version, null: false, default: 1 unless column_exists?(:personas, :version)
      t.text :summary unless column_exists?(:personas, :summary)
      t.text :prompt_md unless column_exists?(:personas, :prompt_md)
      t.text :tags, array: true unless column_exists?(:personas, :tags)
      t.text :notes unless column_exists?(:personas, :notes)
      t.datetime :updated_at unless column_exists?(:personas, :updated_at)
    end

    change_table :rulesets do |t|
      t.integer :version, null: false, default: 1 unless column_exists?(:rulesets, :version)
      t.text :summary unless column_exists?(:rulesets, :summary)
      t.text :rules_md unless column_exists?(:rulesets, :rules_md)
      t.text :tags, array: true unless column_exists?(:rulesets, :tags)
      t.text :notes unless column_exists?(:rulesets, :notes)
      t.datetime :updated_at unless column_exists?(:rulesets, :updated_at)
    end

    create_table :drivers do |t|
      t.text :name, null: false
      t.integer :version, null: false, default: 1
      t.text :summary
      t.text :prompt_md
      t.text :tags, array: true
      t.text :notes
      t.timestamps
    end
    add_index :drivers, :name, unique: true
  end
end
