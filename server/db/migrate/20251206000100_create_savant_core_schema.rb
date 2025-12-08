class CreateSavantCoreSchema < ActiveRecord::Migration[7.1]
  def change
    # Indexer core tables
    create_table :repos, if_not_exists: true do |t|
      t.text :name, null: false
      t.text :root_path, null: false
    end
    add_index :repos, :name, unique: true, if_not_exists: true

    create_table :files, if_not_exists: true do |t|
      t.references :repo, null: false, foreign_key: { on_delete: :cascade }
      t.text :repo_name, null: false
      t.text :rel_path, null: false
      t.bigint :size_bytes, null: false
      t.bigint :mtime_ns, null: false
    end
    add_index :files, :repo_name, if_not_exists: true
    add_index :files, :repo_id, if_not_exists: true
    add_index :files, [:repo_id, :rel_path], unique: true, if_not_exists: true

    create_table :blobs, if_not_exists: true do |t|
      t.text :hash, null: false
      t.bigint :byte_len, null: false
    end
    add_index :blobs, :hash, unique: true, if_not_exists: true

    create_table :file_blob_map, if_not_exists: true, id: false do |t|
      t.bigint :file_id, null: false
      t.bigint :blob_id, null: false
    end
    begin
      add_foreign_key :file_blob_map, :files, column: :file_id, on_delete: :cascade, if_not_exists: true
    rescue NoMethodError
      begin
        add_foreign_key :file_blob_map, :files, column: :file_id, on_delete: :cascade
      rescue StandardError
      end
    end
    begin
      add_foreign_key :file_blob_map, :blobs, column: :blob_id, on_delete: :cascade, if_not_exists: true
    rescue NoMethodError
      begin
        add_foreign_key :file_blob_map, :blobs, column: :blob_id, on_delete: :cascade
      rescue StandardError
      end
    end
    begin
      execute "ALTER TABLE file_blob_map ADD PRIMARY KEY (file_id)"
    rescue StandardError
      # already has PK
    end

    create_table :chunks, if_not_exists: true do |t|
      t.references :blob, null: false, foreign_key: { on_delete: :cascade }
      t.integer :idx, null: false
      t.text :lang
      t.text :chunk_text, null: false
    end
    add_index :chunks, :blob_id, if_not_exists: true

    reversible do |dir|
      dir.up do
        # FTS GIN index on chunk_text
        execute "CREATE INDEX IF NOT EXISTS idx_chunks_fts ON chunks USING GIN (to_tsvector('english', chunk_text))"
      end
      dir.down do
        execute "DROP INDEX IF EXISTS idx_chunks_fts"
      end
    end

    # App entities
    create_table :personas, if_not_exists: true do |t|
      t.text :name, null: false
      t.text :content
      t.datetime :created_at, null: false, default: -> { 'NOW()' }
    end
    add_index :personas, :name, unique: true, if_not_exists: true

    create_table :rulesets, if_not_exists: true do |t|
      t.text :name, null: false
      t.text :content
      t.datetime :created_at, null: false, default: -> { 'NOW()' }
    end
    add_index :rulesets, :name, unique: true, if_not_exists: true

    create_table :agents, if_not_exists: true do |t|
      t.text :name, null: false
      t.bigint :persona_id
      t.text :driver_prompt
      t.integer :rule_set_ids, array: true, default: []
      t.boolean :favorite, null: false, default: false
      t.integer :run_count, null: false, default: 0
      t.datetime :last_run_at
      t.datetime :created_at, null: false, default: -> { 'NOW()' }
      t.datetime :updated_at, null: false, default: -> { 'NOW()' }
    end
    add_index :agents, :name, unique: true, if_not_exists: true
    add_index :agents, :persona_id, if_not_exists: true
    begin
      add_foreign_key :agents, :personas, column: :persona_id, on_delete: :nullify, if_not_exists: true
    rescue NoMethodError
      begin
        add_foreign_key :agents, :personas, column: :persona_id, on_delete: :nullify
      rescue StandardError
      end
    end

    create_table :agent_runs, if_not_exists: true do |t|
      t.bigint :agent_id
      t.text :input
      t.text :output_summary
      t.text :status
      t.bigint :duration_ms
      t.datetime :created_at, null: false, default: -> { 'NOW()' }
      t.jsonb :full_transcript
    end
    add_index :agent_runs, :agent_id, if_not_exists: true
    begin
      add_foreign_key :agent_runs, :agents, column: :agent_id, on_delete: :cascade, if_not_exists: true
    rescue NoMethodError
      begin
        add_foreign_key :agent_runs, :agents, column: :agent_id, on_delete: :cascade
      rescue StandardError
      end
    end

    create_table :workflows, if_not_exists: true do |t|
      t.text :name, null: false
      t.text :description
      t.jsonb :graph
      t.boolean :favorite, null: false, default: false
      t.integer :run_count, null: false, default: 0
      t.datetime :created_at, null: false, default: -> { 'NOW()' }
      t.datetime :updated_at, null: false, default: -> { 'NOW()' }
    end
    add_index :workflows, :name, unique: true, if_not_exists: true

    create_table :workflow_steps, if_not_exists: true do |t|
      t.references :workflow, null: false, foreign_key: { on_delete: :cascade }
      t.text :name, null: false
      t.text :step_type, null: false
      t.jsonb :config
      t.integer :position
    end
    add_index :workflow_steps, :workflow_id, if_not_exists: true

    create_table :workflow_runs, if_not_exists: true do |t|
      t.references :workflow, null: false, foreign_key: { on_delete: :cascade }
      t.text :input
      t.text :output
      t.text :status
      t.bigint :duration_ms
      t.datetime :created_at, null: false, default: -> { 'NOW()' }
      t.jsonb :transcript
    end
    add_index :workflow_runs, :workflow_id, if_not_exists: true
  end
end
