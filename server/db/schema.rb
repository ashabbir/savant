# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 202512140001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "agent_runs", force: :cascade do |t|
    t.bigint "agent_id"
    t.text "input"
    t.text "output_summary"
    t.text "status"
    t.bigint "duration_ms"
    t.jsonb "full_transcript"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.index ["agent_id"], name: "index_agent_runs_on_agent_id"
  end

  create_table "agents", force: :cascade do |t|
    t.text "name", null: false
    t.bigint "persona_id"
    t.text "driver_prompt"
    t.text "driver_name"
    t.text "instructions"
    t.integer "rule_set_ids", array: true
    t.boolean "favorite", default: false, null: false
    t.integer "run_count", default: 0, null: false
    t.datetime "last_run_at"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.integer "model_id"
    t.index ["name"], name: "index_agents_on_name", unique: true
    t.index ["persona_id"], name: "index_agents_on_persona_id"
  end

  create_table "blobs", force: :cascade do |t|
    t.text "hash", null: false
    t.bigint "byte_len", null: false
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.index ["hash"], name: "index_blobs_on_hash", unique: true
  end

  create_table "chunks", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.integer "idx", null: false
    t.text "lang"
    t.text "chunk_text", null: false
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.index "to_tsvector('english'::regconfig, chunk_text)", name: "idx_chunks_fts", using: :gin
    t.index ["blob_id"], name: "index_chunks_on_blob_id"
  end

  create_table "drivers", force: :cascade do |t|
    t.text "name", null: false
    t.integer "version", default: 1, null: false
    t.text "summary"
    t.text "prompt_md"
    t.text "tags", array: true
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_drivers_on_name", unique: true
  end

  create_table "file_blob_map", primary_key: "file_id", id: :bigint, default: nil, force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.index ["blob_id"], name: "index_file_blob_map_on_blob_id"
    t.index ["file_id"], name: "index_file_blob_map_on_file_id"
  end

  create_table "files", force: :cascade do |t|
    t.bigint "repo_id", null: false
    t.text "repo_name", null: false
    t.text "rel_path", null: false
    t.bigint "size_bytes", null: false
    t.bigint "mtime_ns", null: false
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.index ["repo_id", "rel_path"], name: "index_files_on_repo_id_and_rel_path", unique: true
    t.index ["repo_name"], name: "index_files_on_repo_name"
  end

  create_table "llm_agent_model_assignments", id: false, force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.bigint "model_id", null: false
    t.index ["agent_id"], name: "index_llm_agent_model_assignments_on_agent_id"
    t.index ["model_id"], name: "index_llm_agent_model_assignments_on_model_id"
  end

  create_table "llm_agents", force: :cascade do |t|
    t.text "name", null: false
    t.text "description"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.index ["name"], name: "index_llm_agents_on_name", unique: true
  end

  create_table "llm_cache", force: :cascade do |t|
    t.bigint "provider_id", null: false
    t.text "key", null: false
    t.jsonb "value"
    t.timestamptz "expires_at", null: false
    t.index ["provider_id", "key"], name: "index_llm_cache_on_provider_id_and_key", unique: true
    t.index ["provider_id"], name: "index_llm_cache_on_provider_id"
  end

  create_table "llm_models", force: :cascade do |t|
    t.bigint "provider_id", null: false
    t.text "provider_model_id", null: false
    t.text "display_name", null: false
    t.text "modality", default: [], array: true
    t.integer "context_window"
    t.decimal "input_cost_per_1k"
    t.decimal "output_cost_per_1k"
    t.boolean "enabled", default: true
    t.jsonb "meta", default: {}
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.index ["provider_id", "provider_model_id"], name: "index_llm_models_on_provider_id_and_provider_model_id", unique: true
    t.index ["provider_id"], name: "index_llm_models_on_provider_id"
  end

  create_table "llm_providers", force: :cascade do |t|
    t.text "name", null: false
    t.text "provider_type", null: false
    t.text "base_url"
    t.binary "encrypted_api_key"
    t.binary "api_key_nonce"
    t.binary "api_key_tag"
    t.text "status", default: "unknown"
    t.timestamptz "last_validated_at"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.index ["name"], name: "index_llm_providers_on_name", unique: true
  end

  create_table "personas", force: :cascade do |t|
    t.text "name", null: false
    t.text "content"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.integer "version", default: 1, null: false
    t.text "summary"
    t.text "prompt_md"
    t.text "tags", array: true
    t.text "notes"
    t.index ["name"], name: "index_personas_on_name", unique: true
  end

  create_table "repos", force: :cascade do |t|
    t.text "name", null: false
    t.text "root_path", null: false
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.index ["name"], name: "index_repos_on_name", unique: true
  end

  create_table "rulesets", force: :cascade do |t|
    t.text "name", null: false
    t.text "content"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.integer "version", default: 1, null: false
    t.text "summary"
    t.text "rules_md"
    t.text "tags", array: true
    t.text "notes"
    t.index ["name"], name: "index_rulesets_on_name", unique: true
  end

  create_table "think_workflows", force: :cascade do |t|
    t.text "workflow_id", null: false
    t.text "name"
    t.text "description"
    t.integer "version", default: 1, null: false
    t.jsonb "steps", default: {}, null: false
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.index ["workflow_id"], name: "index_think_workflows_on_workflow_id", unique: true
  end

  add_foreign_key "agent_runs", "agents", on_delete: :cascade
  add_foreign_key "agents", "llm_models", column: "model_id", on_delete: :nullify
  add_foreign_key "agents", "personas", on_delete: :nullify
  add_foreign_key "chunks", "blobs", on_delete: :cascade
  add_foreign_key "file_blob_map", "blobs", on_delete: :cascade
  add_foreign_key "file_blob_map", "files", on_delete: :cascade
  add_foreign_key "files", "repos", on_delete: :cascade
  add_foreign_key "llm_agent_model_assignments", "llm_agents", column: "agent_id", on_delete: :cascade
  add_foreign_key "llm_agent_model_assignments", "llm_models", column: "model_id", on_delete: :cascade
  add_foreign_key "llm_cache", "llm_providers", column: "provider_id", on_delete: :cascade
  add_foreign_key "llm_models", "llm_providers", column: "provider_id", on_delete: :cascade
end
