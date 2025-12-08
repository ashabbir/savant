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

ActiveRecord::Schema[7.2].define(version: 2025_12_06_010100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "agent_runs", force: :cascade do |t|
    t.bigint "agent_id"
    t.text "input"
    t.text "output_summary"
    t.text "status"
    t.bigint "duration_ms"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.jsonb "full_transcript"
    t.index ["agent_id"], name: "idx_agent_runs_agent"
    t.index ["agent_id"], name: "index_agent_runs_on_agent_id"
  end

  create_table "agents", force: :cascade do |t|
    t.text "name", null: false
    t.bigint "persona_id"
    t.text "driver_prompt"
    t.integer "rule_set_ids", default: [], array: true
    t.boolean "favorite", default: false, null: false
    t.integer "run_count", default: 0, null: false
    t.datetime "last_run_at"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.text "driver_name"
    t.index ["name"], name: "index_agents_on_name", unique: true
    t.index ["persona_id"], name: "idx_agents_persona"
    t.index ["persona_id"], name: "index_agents_on_persona_id"
  end

  create_table "blobs", force: :cascade do |t|
    t.text "hash", null: false
    t.bigint "byte_len", null: false
    t.index ["hash"], name: "index_blobs_on_hash", unique: true
  end

  create_table "chunks", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.integer "idx", null: false
    t.text "lang"
    t.text "chunk_text", null: false
    t.index "to_tsvector('english'::regconfig, chunk_text)", name: "idx_chunks_fts", using: :gin
    t.index ["blob_id"], name: "idx_chunks_blob"
    t.index ["blob_id"], name: "index_chunks_on_blob_id"
  end

  create_table "file_blob_map", primary_key: "file_id", id: :bigint, default: nil, force: :cascade do |t|
    t.bigint "blob_id", null: false
  end

  create_table "files", force: :cascade do |t|
    t.bigint "repo_id", null: false
    t.text "repo_name", null: false
    t.text "rel_path", null: false
    t.bigint "size_bytes", null: false
    t.bigint "mtime_ns", null: false
    t.index ["repo_id", "rel_path"], name: "index_files_on_repo_id_and_rel_path", unique: true
    t.index ["repo_id"], name: "idx_files_repo_id"
    t.index ["repo_id"], name: "index_files_on_repo_id"
    t.index ["repo_name"], name: "idx_files_repo_name"
    t.index ["repo_name"], name: "index_files_on_repo_name"
  end

  create_table "personas", force: :cascade do |t|
    t.text "name", null: false
    t.text "content"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.index ["name"], name: "index_personas_on_name", unique: true
  end

  create_table "repos", force: :cascade do |t|
    t.text "name", null: false
    t.text "root_path", null: false
    t.index ["name"], name: "index_repos_on_name", unique: true
  end

  create_table "rulesets", force: :cascade do |t|
    t.text "name", null: false
    t.text "content"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.index ["name"], name: "index_rulesets_on_name", unique: true
  end

  create_table "workflow_runs", force: :cascade do |t|
    t.bigint "workflow_id", null: false
    t.text "input"
    t.text "output"
    t.text "status"
    t.bigint "duration_ms"
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.jsonb "transcript"
    t.index ["workflow_id"], name: "idx_workflow_runs_workflow"
    t.index ["workflow_id"], name: "index_workflow_runs_on_workflow_id"
  end

  create_table "workflow_steps", force: :cascade do |t|
    t.bigint "workflow_id", null: false
    t.text "name", null: false
    t.text "step_type", null: false
    t.jsonb "config"
    t.integer "position"
    t.index ["workflow_id"], name: "idx_workflow_steps_workflow"
    t.index ["workflow_id"], name: "index_workflow_steps_on_workflow_id"
  end

  create_table "workflows", force: :cascade do |t|
    t.text "name", null: false
    t.text "description"
    t.jsonb "graph"
    t.boolean "favorite", default: false, null: false
    t.integer "run_count", default: 0, null: false
    t.datetime "created_at", default: -> { "now()" }, null: false
    t.datetime "updated_at", default: -> { "now()" }, null: false
    t.index ["name"], name: "index_workflows_on_name", unique: true
  end

  add_foreign_key "agent_runs", "agents", on_delete: :cascade
  add_foreign_key "agents", "personas", on_delete: :nullify
  add_foreign_key "chunks", "blobs", on_delete: :cascade
  add_foreign_key "file_blob_map", "blobs", on_delete: :cascade
  add_foreign_key "file_blob_map", "files", on_delete: :cascade
  add_foreign_key "files", "repos", on_delete: :cascade
  add_foreign_key "workflow_runs", "workflows", on_delete: :cascade
  add_foreign_key "workflow_steps", "workflows", on_delete: :cascade
end
