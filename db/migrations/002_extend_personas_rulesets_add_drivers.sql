-- Extend personas table with version, summary, prompt_md, tags, notes
ALTER TABLE personas ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE personas ADD COLUMN IF NOT EXISTS summary TEXT;
ALTER TABLE personas ADD COLUMN IF NOT EXISTS prompt_md TEXT;
ALTER TABLE personas ADD COLUMN IF NOT EXISTS tags TEXT[];
ALTER TABLE personas ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE personas ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Extend rulesets table with version, summary, rules_md, tags, notes
ALTER TABLE rulesets ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE rulesets ADD COLUMN IF NOT EXISTS summary TEXT;
ALTER TABLE rulesets ADD COLUMN IF NOT EXISTS rules_md TEXT;
ALTER TABLE rulesets ADD COLUMN IF NOT EXISTS tags TEXT[];
ALTER TABLE rulesets ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE rulesets ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Create drivers table (prompt templates for agents)
CREATE TABLE IF NOT EXISTS drivers (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  version INTEGER NOT NULL DEFAULT 1,
  summary TEXT,
  prompt_md TEXT,
  tags TEXT[],
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add driver_name column to agents if not exists (references drivers by name)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'agents' AND column_name = 'driver_name'
  ) THEN
    ALTER TABLE agents ADD COLUMN driver_name TEXT;
  END IF;
END $$;
