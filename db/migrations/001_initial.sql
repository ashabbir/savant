-- Initial schema (indexer + app) — idempotent

-- Indexer core tables
CREATE TABLE IF NOT EXISTS repos (
  id SERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  root_path TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS files (
  id SERIAL PRIMARY KEY,
  repo_id INTEGER NOT NULL REFERENCES repos(id) ON DELETE CASCADE,
  repo_name TEXT NOT NULL,
  rel_path TEXT NOT NULL,
  size_bytes BIGINT NOT NULL,
  mtime_ns BIGINT NOT NULL,
  UNIQUE(repo_id, rel_path)
);
CREATE INDEX IF NOT EXISTS idx_files_repo_name ON files(repo_name);
CREATE INDEX IF NOT EXISTS idx_files_repo_id ON files(repo_id);

CREATE TABLE IF NOT EXISTS blobs (
  id SERIAL PRIMARY KEY,
  hash TEXT UNIQUE NOT NULL,
  byte_len BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS file_blob_map (
  file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  blob_id INTEGER NOT NULL REFERENCES blobs(id) ON DELETE CASCADE,
  PRIMARY KEY(file_id)
);

CREATE TABLE IF NOT EXISTS chunks (
  id SERIAL PRIMARY KEY,
  blob_id INTEGER NOT NULL REFERENCES blobs(id) ON DELETE CASCADE,
  idx INTEGER NOT NULL,
  lang TEXT,
  chunk_text TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_chunks_blob ON chunks(blob_id);
CREATE INDEX IF NOT EXISTS idx_chunks_fts ON chunks USING GIN (to_tsvector('english', chunk_text));

-- App entities: personas, rulesets, agents, runs, workflows, steps, runs
CREATE TABLE IF NOT EXISTS personas (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  content TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rulesets (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  content TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS agents (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  persona_id INTEGER REFERENCES personas(id) ON DELETE SET NULL,
  driver_prompt TEXT,
  rule_set_ids INTEGER[],
  favorite BOOLEAN NOT NULL DEFAULT FALSE,
  run_count INTEGER NOT NULL DEFAULT 0,
  last_run_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_agents_persona ON agents(persona_id);

CREATE TABLE IF NOT EXISTS agent_runs (
  id SERIAL PRIMARY KEY,
  agent_id INTEGER REFERENCES agents(id) ON DELETE CASCADE,
  input TEXT,
  output_summary TEXT,
  status TEXT,
  duration_ms BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  full_transcript JSONB
);
CREATE INDEX IF NOT EXISTS idx_agent_runs_agent ON agent_runs(agent_id);

CREATE TABLE IF NOT EXISTS workflows (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  graph JSONB,
  favorite BOOLEAN NOT NULL DEFAULT FALSE,
  run_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS workflow_steps (
  id SERIAL PRIMARY KEY,
  workflow_id INTEGER NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  step_type TEXT NOT NULL,
  config JSONB,
  position INTEGER
);
CREATE INDEX IF NOT EXISTS idx_workflow_steps_workflow ON workflow_steps(workflow_id);

CREATE TABLE IF NOT EXISTS workflow_runs (
  id SERIAL PRIMARY KEY,
  workflow_id INTEGER NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
  input TEXT,
  output TEXT,
  status TEXT,
  duration_ms BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  transcript JSONB
);
CREATE INDEX IF NOT EXISTS idx_workflow_runs_workflow ON workflow_runs(workflow_id);

