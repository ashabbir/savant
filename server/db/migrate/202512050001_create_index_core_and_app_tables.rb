class CreateIndexCoreAndAppTables < ActiveRecord::Migration[7.2]
  def change
    create_table :repos do |t|
      t.text :name, null: false
      t.text :root_path, null: false
      t.timestamps default: -> { 'NOW()' }
    end
    add_index :repos, :name, unique: true

    create_table :files do |t|
      t.references :repo, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.text :repo_name, null: false
      t.text :rel_path, null: false
      t.bigint :size_bytes, null: false
      t.bigint :mtime_ns, null: false
      t.timestamps default: -> { 'NOW()' }
    end
    add_index :files, :repo_name
    add_index :files, [:repo_id, :rel_path], unique: true

    create_table :blobs do |t|
      t.text :hash, null: false
      t.bigint :byte_len, null: false
      t.timestamps default: -> { 'NOW()' }
    end
    add_index :blobs, :hash, unique: true

    create_table :file_blob_map, id: false do |t|
      t.references :file, null: false, foreign_key: { on_delete: :cascade }
      t.references :blob, null: false, foreign_key: { on_delete: :cascade }
    end
    reversible do |dir|
      dir.up { execute 'ALTER TABLE file_blob_map ADD PRIMARY KEY (file_id)' }
    end

    create_table :chunks do |t|
      t.references :blob, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :idx, null: false
      t.text :lang
      t.text :chunk_text, null: false
      t.timestamps default: -> { 'NOW()' }
    end
    add_index :chunks, :blob_id
    execute <<~SQL
      CREATE INDEX IF NOT EXISTS idx_chunks_fts ON chunks USING GIN (to_tsvector('english', chunk_text));
    SQL

    create_table :personas do |t|
      t.text :name, null: false
      t.text :content
      t.timestamps default: -> { 'NOW()' }
    end
    add_index :personas, :name, unique: true

    create_table :rulesets do |t|
      t.text :name, null: false
      t.text :content
      t.timestamps default: -> { 'NOW()' }
    end
    add_index :rulesets, :name, unique: true

    create_table :agents do |t|
      t.text :name, null: false
      t.references :persona, foreign_key: { on_delete: :nullify }, index: false
      t.text :driver_prompt
      t.text :driver_name
      t.text :instructions
      t.integer :rule_set_ids, array: true
      t.text :allowed_tools, array: true
      t.boolean :favorite, null: false, default: false
      t.integer :run_count, null: false, default: 0
      t.datetime :last_run_at
      t.timestamps default: -> { 'NOW()' }
    end
    add_index :agents, :name, unique: true
    add_index :agents, :persona_id

    create_table :agent_runs do |t|
      t.references :agent, foreign_key: { on_delete: :cascade }, index: false
      t.text :input
      t.text :output_summary
      t.text :status
      t.bigint :duration_ms
      t.jsonb :full_transcript
      t.timestamps default: -> { 'NOW()' }
    end
    add_index :agent_runs, :agent_id

    # workflows table no longer needed; deprecated in favour of think_workflows
  end
end
