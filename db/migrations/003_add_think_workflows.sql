-- Create think_workflows table for storing workflow definitions
CREATE TABLE IF NOT EXISTS think_workflows (
  id SERIAL PRIMARY KEY,
  workflow_id TEXT NOT NULL UNIQUE,
  name TEXT,
  description TEXT,
  driver_version TEXT DEFAULT 'stable',
  rules TEXT[],
  version INTEGER NOT NULL DEFAULT 1,
  steps JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_think_workflows_workflow_id ON think_workflows(workflow_id);
