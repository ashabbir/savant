#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Purpose: Postgres connection + schema helpers.
#
# Provides a small wrapper around the pg connection used across Savant. It
# includes helpers to create/migrate core tables, ensure the FTS GIN index, and
# run transactional blocks. CRUD for indexing lives in BlobStore; this class is
# intentionally focused on connection lifecycle and schema operations.

require 'pg'
require 'json'
require 'pathname'

module Savant
  module Framework
    # Connection + schema helper around Postgres.
    #
    # Purpose: Centralize DB lifecycle and schema/CRUD helpers used by the
    # indexer and context engines. Keeps business logic out of SQL access.
    #
    # Typical usage creates an instance per process and reuses a single
    # connection; callers may use transaction helpers for multi-step writes.
    # rubocop:disable Metrics/ClassLength
    class DB
      # @param url [String] Postgres connection URL (uses `ENV['DATABASE_URL']`).
      def initialize(url = ENV.fetch('DATABASE_URL', nil))
        @url = url
        @mutex = Mutex.new
        @conn = connect!
        configure_client_min_messages
        # Zero-setup: apply non-destructive migrations automatically unless disabled
        begin
          auto = (ENV['SAVANT_AUTO_MIGRATE'] || '1') != '0'
          if auto
            ensure_schema_migrations!
            apply_migrations
            ensure_fts
          end
        rescue StandardError
          # best-effort; do not crash caller if migrations cannot be applied
        end
      end

      def connection
        ensure_connection!
        @conn
      end

      def with_connection
        @mutex.synchronize do
          ensure_connection!
          yield @conn
        end
      rescue PG::UnableToSend, PG::ConnectionBad
        @mutex.synchronize do
          reconnect!
          yield @conn
        end
      end

      def exec(sql)
        with_connection { |conn| conn.exec(sql) }
      end

      def exec_params(sql, params)
        with_connection { |conn| conn.exec_params(sql, params) }
      end

      def reconnect!
        begin
          @conn&.close
        rescue StandardError
          nil
        end
        @conn = connect!
        configure_client_min_messages
      end

      def ensure_connection!
        reconnect! if @conn.nil? || @conn.finished? || @conn.status != PG::CONNECTION_OK
      rescue PG::Error
        reconnect!
      end

      # Execute a block inside a DB transaction.
      # @yield Runs inside BEGIN/COMMIT; ROLLBACK on errors.
      # @return [Object] yields return value.
      def with_transaction
        exec('BEGIN')
        begin
          yield
          exec('COMMIT')
        rescue StandardError => e
          begin
            exec('ROLLBACK')
          rescue StandardError
            nil
          end
          raise e
        end
      end

      def close
        @conn&.close
        @conn = nil
      end

      # Clean up idle connections in the Postgres server
      # Call this periodically to prevent connection exhaustion
      def cleanup_idle_connections
        with_connection do |conn|
          conn.exec(<<~SQL)
            SELECT pg_terminate_backend(pid)
            FROM pg_stat_activity
            WHERE datname = current_database()
              AND pid != pg_backend_pid()
              AND state = 'idle'
              AND state_change < now() - interval '10 minutes'
          SQL
        end
      rescue StandardError => e
        warn "Failed to cleanup idle connections: #{e.message}"
      end

      # Drop and recreate all schema tables and indexes.
      # @return [true]
      def migrate_tables
        # Destructive reset: drop and recreate all tables/indexes
        # App tables (agents/personas/rules):
        exec('DROP TABLE IF EXISTS agent_runs CASCADE')
        exec('DROP TABLE IF EXISTS agents CASCADE')
        exec('DROP TABLE IF EXISTS rulesets CASCADE')
        exec('DROP TABLE IF EXISTS personas CASCADE')

        # Indexer tables:
        exec('DROP TABLE IF EXISTS file_blob_map CASCADE')
        exec('DROP TABLE IF EXISTS chunks CASCADE')
        exec('DROP TABLE IF EXISTS files CASCADE')
        exec('DROP TABLE IF EXISTS blobs CASCADE')
        exec('DROP TABLE IF EXISTS repos CASCADE')

        exec(<<~SQL)
          CREATE TABLE repos (
            id SERIAL PRIMARY KEY,
            name TEXT UNIQUE NOT NULL,
            root_path TEXT NOT NULL
          );
        SQL

        exec(<<~SQL)
          CREATE TABLE files (
            id SERIAL PRIMARY KEY,
            repo_id INTEGER NOT NULL REFERENCES repos(id) ON DELETE CASCADE,
            repo_name TEXT NOT NULL,
            rel_path TEXT NOT NULL,
            size_bytes BIGINT NOT NULL,
            mtime_ns BIGINT NOT NULL,
            UNIQUE(repo_id, rel_path)
          );
        SQL
        exec('CREATE INDEX idx_files_repo_name ON files(repo_name)')
        exec('CREATE INDEX idx_files_repo_id ON files(repo_id)')

        exec(<<~SQL)
          CREATE TABLE blobs (
            id SERIAL PRIMARY KEY,
            hash TEXT UNIQUE NOT NULL,
            byte_len BIGINT NOT NULL
          );
        SQL

        exec(<<~SQL)
          CREATE TABLE file_blob_map (
            file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
            blob_id INTEGER NOT NULL REFERENCES blobs(id) ON DELETE CASCADE,
            PRIMARY KEY(file_id)
          );
        SQL

        exec(<<~SQL)
          CREATE TABLE chunks (
            id SERIAL PRIMARY KEY,
            blob_id INTEGER NOT NULL REFERENCES blobs(id) ON DELETE CASCADE,
            idx INTEGER NOT NULL,
            lang TEXT,
            chunk_text TEXT NOT NULL
          );
        SQL
        exec('CREATE INDEX idx_chunks_blob ON chunks(blob_id)')

        # App schema — agents/personas/rules
        exec(<<~SQL)
          CREATE TABLE personas (
            id SERIAL PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            content TEXT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
          );
        SQL

        exec(<<~SQL)
          CREATE TABLE rulesets (
            id SERIAL PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            content TEXT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
          );
        SQL

        exec(<<~SQL)
          CREATE TABLE agents (
            id SERIAL PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            persona_id INTEGER REFERENCES personas(id) ON DELETE SET NULL,
            driver_prompt TEXT,
            driver_name TEXT,
            instructions TEXT,
            rule_set_ids INTEGER[],
            favorite BOOLEAN NOT NULL DEFAULT FALSE,
            run_count INTEGER NOT NULL DEFAULT 0,
            last_run_at TIMESTAMPTZ,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
          );
        SQL
        exec('CREATE INDEX idx_agents_persona ON agents(persona_id)')

        exec(<<~SQL)
          CREATE TABLE agent_runs (
            id SERIAL PRIMARY KEY,
            agent_id INTEGER REFERENCES agents(id) ON DELETE CASCADE,
            input TEXT,
            output_summary TEXT,
            status TEXT,
            duration_ms BIGINT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            full_transcript JSONB
          );
        SQL
        exec('CREATE INDEX idx_agent_runs_agent ON agent_runs(agent_id)')

        true
      end

      # Ensure the GIN FTS index on `chunks.chunk_text` exists.
      # @return [true]
      def ensure_fts
        return true unless table_exists?('chunks')

        exec(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_chunks_fts ON chunks USING GIN (to_tsvector('english', chunk_text));
        SQL
        true
      rescue PG::UndefinedTable
        true
      end

      def table_exists?(name)
        res = exec_params("SELECT to_regclass($1)", [name.to_s])
        res.ntuples.positive? && !res[0]['to_regclass'].nil?
      end

      # Apply versioned migrations from db/migrations non-destructively.
      # Returns an array of hashes { version:, file: }.
      def apply_migrations(dir = default_migrations_dir)
        ensure_schema_migrations!
        files = Dir.glob(File.join(dir, '*')).sort
        applied = []
        files.each do |path|
          next unless path.end_with?('.sql')

          version = File.basename(path).sub(/\.(sql|rb)\z/, '')
          next if migration_applied?(version)

          sql = File.read(path)
          with_transaction do
            exec(sql)
            mark_migration_applied!(version)
          end
          applied << { version: version, file: File.basename(path) }
        end
        applied
      end

      # Fetch an existing blob id by hash or insert a new blob.
      # @param hash [String]
      # @param byte_len [Integer]
      # @return [Integer] blob id
      def find_or_create_blob(hash, byte_len)
        res = exec_params('SELECT id FROM blobs WHERE hash=$1', [hash])
        return res[0]['id'].to_i if res.ntuples.positive?

        res = exec_params('INSERT INTO blobs(hash, byte_len) VALUES($1,$2) RETURNING id', [hash, byte_len])
        res[0]['id'].to_i
      end

      # Replace all chunks for a blob id.
      # @param blob_id [Integer]
      # @param chunks [Array<Array(Integer,String,String)>>] [idx, lang, text]
      # @return [true]
      def replace_chunks(blob_id, chunks)
        exec_params('DELETE FROM chunks WHERE blob_id=$1', [blob_id])
        chunks.each do |idx, lang, text|
          exec_params('INSERT INTO chunks(blob_id, idx, lang, chunk_text) VALUES($1,$2,$3,$4)',
                      [blob_id, idx, lang, text])
        end
        true
      end

      # Fetch an existing repo id by name or insert it with path.
      # @return [Integer] repo id
      def find_or_create_repo(name, root)
        res = exec_params('SELECT id, root_path FROM repos WHERE name=$1', [name])
        if res.ntuples.positive?
          id = res[0]['id'].to_i
          existing_root = res[0]['root_path']
          begin
            # If the repo already exists but the root_path has changed (e.g., different host mount), update it
            exec_params('UPDATE repos SET root_path=$1 WHERE id=$2', [root, id]) if existing_root.to_s != root.to_s && !root.to_s.empty?
          rescue StandardError
            # best-effort; continue with existing id
          end
          return id
        end

        res = exec_params('INSERT INTO repos(name, root_path, created_at, updated_at) VALUES($1,$2,NOW(),NOW()) RETURNING id', [name, root])
        res[0]['id'].to_i
      end

      # Insert or update a file row and return its id.
      # @return [Integer] file id
      def upsert_file(repo_id, repo_name, rel_path, size_bytes, mtime_ns)
        res = exec_params(
          <<~SQL, [repo_id, repo_name, rel_path, size_bytes, mtime_ns]
            INSERT INTO files(repo_id, repo_name, rel_path, size_bytes, mtime_ns)
            VALUES($1,$2,$3,$4,$5)
            ON CONFLICT (repo_id, rel_path)
            DO UPDATE SET repo_name=EXCLUDED.repo_name, size_bytes=EXCLUDED.size_bytes, mtime_ns=EXCLUDED.mtime_ns
            RETURNING id
          SQL
        )
        res[0]['id'].to_i
      end

      # Map a file id to a blob id (upsert).
      # @return [true]
      def map_file_to_blob(file_id, blob_id)
        exec_params(
          <<~SQL, [file_id, blob_id]
            INSERT INTO file_blob_map(file_id, blob_id)
            VALUES($1,$2)
            ON CONFLICT (file_id) DO UPDATE SET blob_id=EXCLUDED.blob_id
          SQL
        )
        true
      end

      # Check if a file row exists for a repo id and relative path.
      # @param repo_id [Integer]
      # @param rel_path [String]
      # @return [Boolean]
      def file_exists?(repo_id, rel_path)
        res = exec_params('SELECT 1 FROM files WHERE repo_id=$1 AND rel_path=$2 LIMIT 1', [repo_id, rel_path])
        res.ntuples.positive?
      end

      # Delete files for a repo not present in `keep_rels`.
      # @param repo_id [Integer]
      # @param keep_rels [Array<String>]
      # @return [true]
      def delete_missing_files(repo_id, keep_rels)
        if keep_rels.empty?
          exec_params('DELETE FROM files WHERE repo_id=$1', [repo_id])
        else
          # Use a single array parameter to avoid very large parameter lists
          sql = 'DELETE FROM files WHERE repo_id=$1 AND NOT (rel_path = ANY($2::text[]))'
          exec_params(sql, [repo_id, text_array_encoder.encode(keep_rels)])
        end
        true
      end

      # Delete a repository and all its data by name.
      # @return [Integer] number of repos deleted (0/1)
      def delete_repo_by_name(name)
        res = exec_params('SELECT id FROM repos WHERE name=$1', [name])
        return 0 if res.ntuples.zero?

        rid = res[0]['id']
        exec_params('DELETE FROM repos WHERE id=$1', [rid])
        1
      end

      # Truncate all data from all tables (destructive).
      # @return [true]
      def delete_all_data
        exec('DELETE FROM file_blob_map')
        exec('DELETE FROM files')
        exec('DELETE FROM chunks')
        exec('DELETE FROM blobs')
        exec('DELETE FROM repos')
        true
      end

      # List repos along with the first README chunk stored in the DB.
      # @param filter [String, nil] optional substring filter on repo name
      # @return [Array<Hash>] { name:, readme_text: }
      def list_repos_with_readme(filter: nil)
        params = []
        where_clause = ''
        unless filter.to_s.strip.empty?
          params << "%#{filter}%"
          where_clause = "WHERE r.name ILIKE $#{params.length}"
        end

        sql = <<~SQL
          SELECT r.name, readme.chunk_text AS readme_text
          FROM repos r
          LEFT JOIN LATERAL (
            SELECT c.chunk_text
            FROM files f
            JOIN file_blob_map fb ON fb.file_id = f.id
            JOIN chunks c ON c.blob_id = fb.blob_id
            WHERE f.repo_id = r.id
              AND LOWER(f.rel_path) LIKE 'readme%'
            ORDER BY f.rel_path ASC, c.idx ASC
            LIMIT 1
          ) readme ON true
          #{where_clause}
          ORDER BY r.name ASC
        SQL

        res = exec_params(sql, params)
        res.map { |row| { name: row['name'], readme_text: row['readme_text'] } }
      end

      # =========================
      # App CRUD: Personas (extended)
      # =========================
      def create_persona(name, content = nil, version: 1, summary: nil, prompt_md: nil, tags: nil, notes: nil)
        tags_encoded = tags.nil? ? nil : text_array_encoder.encode(Array(tags))
        res = exec_params(
          <<~SQL, [name, content, version, summary, prompt_md, tags_encoded, notes]
            INSERT INTO personas(name, content, version, summary, prompt_md, tags, notes, created_at, updated_at)
            VALUES($1, $2, $3, $4, $5, $6, $7, NOW(), NOW())
            ON CONFLICT (name) DO UPDATE SET
              content = COALESCE(EXCLUDED.content, personas.content),
              version = EXCLUDED.version,
              summary = COALESCE(EXCLUDED.summary, personas.summary),
              prompt_md = COALESCE(EXCLUDED.prompt_md, personas.prompt_md),
              tags = COALESCE(EXCLUDED.tags, personas.tags),
              notes = COALESCE(EXCLUDED.notes, personas.notes),
              updated_at = NOW()
            RETURNING id
          SQL
        )
        res[0]['id'].to_i
      end

      def update_persona(name:, version: nil, summary: nil, prompt_md: nil, tags: nil, notes: nil)
        sets = ['updated_at = NOW()']
        params = []
        idx = 1
        unless version.nil?
          sets << "version = $#{idx}"
          params << version
          idx += 1
        end
        unless summary.nil?
          sets << "summary = $#{idx}"
          params << summary
          idx += 1
        end
        unless prompt_md.nil?
          sets << "prompt_md = $#{idx}"
          params << prompt_md
          idx += 1
        end
        unless tags.nil?
          sets << "tags = $#{idx}"
          params << text_array_encoder.encode(Array(tags))
          idx += 1
        end
        unless notes.nil?
          sets << "notes = $#{idx}"
          params << notes
          idx += 1
        end
        params << name
        sql = "UPDATE personas SET #{sets.join(', ')} WHERE name = $#{idx} RETURNING id"
        res = exec_params(sql, params)
        res.ntuples.positive? ? res[0]['id'].to_i : nil
      end

      def get_persona_by_name(name)
        res = exec_params('SELECT * FROM personas WHERE name=$1', [name])
        res.ntuples.positive? ? res[0] : nil
      end

      def list_personas(filter: nil)
        if filter && !filter.to_s.strip.empty?
          q = "%#{filter}%"
          res = exec_params(
            "SELECT * FROM personas WHERE name ILIKE $1 OR summary ILIKE $1 OR array_to_string(tags, ' ') ILIKE $1 ORDER BY name ASC",
            [q]
          )
        else
          res = exec('SELECT * FROM personas ORDER BY name ASC')
        end
        res.to_a
      end

      def delete_persona(name)
        res = exec_params('DELETE FROM personas WHERE name = $1 RETURNING id', [name])
        res.ntuples.positive?
      end

      # =========================
      # App CRUD: Rulesets (extended)
      # =========================
      def create_ruleset(name, content = nil, version: 1, summary: nil, rules_md: nil, tags: nil, notes: nil)
        tags_encoded = tags.nil? ? nil : text_array_encoder.encode(Array(tags))
        res = exec_params(
          <<~SQL, [name, content, version, summary, rules_md, tags_encoded, notes]
            INSERT INTO rulesets(name, content, version, summary, rules_md, tags, notes, created_at, updated_at)
            VALUES($1, $2, $3, $4, $5, $6, $7, NOW(), NOW())
            ON CONFLICT (name) DO UPDATE SET
              content = COALESCE(EXCLUDED.content, rulesets.content),
              version = EXCLUDED.version,
              summary = COALESCE(EXCLUDED.summary, rulesets.summary),
              rules_md = COALESCE(EXCLUDED.rules_md, rulesets.rules_md),
              tags = COALESCE(EXCLUDED.tags, rulesets.tags),
              notes = COALESCE(EXCLUDED.notes, rulesets.notes),
              updated_at = NOW()
            RETURNING id
          SQL
        )
        res[0]['id'].to_i
      end

      def update_ruleset(name:, version: nil, summary: nil, rules_md: nil, tags: nil, notes: nil)
        sets = ['updated_at = NOW()']
        params = []
        idx = 1
        unless version.nil?
          sets << "version = $#{idx}"
          params << version
          idx += 1
        end
        unless summary.nil?
          sets << "summary = $#{idx}"
          params << summary
          idx += 1
        end
        unless rules_md.nil?
          sets << "rules_md = $#{idx}"
          params << rules_md
          idx += 1
        end
        unless tags.nil?
          sets << "tags = $#{idx}"
          params << text_array_encoder.encode(Array(tags))
          idx += 1
        end
        unless notes.nil?
          sets << "notes = $#{idx}"
          params << notes
          idx += 1
        end
        params << name
        sql = "UPDATE rulesets SET #{sets.join(', ')} WHERE name = $#{idx} RETURNING id"
        res = exec_params(sql, params)
        res.ntuples.positive? ? res[0]['id'].to_i : nil
      end

      def get_ruleset_by_name(name)
        res = exec_params('SELECT * FROM rulesets WHERE name=$1', [name])
        res.ntuples.positive? ? res[0] : nil
      end

      def list_rulesets(filter: nil)
        if filter && !filter.to_s.strip.empty?
          q = "%#{filter}%"
          res = exec_params(
            "SELECT * FROM rulesets WHERE name ILIKE $1 OR summary ILIKE $1 OR array_to_string(tags, ' ') ILIKE $1 ORDER BY name ASC",
            [q]
          )
        else
          res = exec('SELECT * FROM rulesets ORDER BY name ASC')
        end
        res.to_a
      end

      def delete_ruleset(name)
        res = exec_params('DELETE FROM rulesets WHERE name = $1 RETURNING id', [name])
        res.ntuples.positive?
      end

      # =========================
      # App CRUD: Drivers
      # =========================
      def create_driver(name:, version: 1, summary: nil, prompt_md: nil, tags: nil, notes: nil)
        tags_encoded = tags.nil? ? nil : text_array_encoder.encode(Array(tags))
        res = exec_params(
          <<~SQL, [name, version, summary, prompt_md, tags_encoded, notes]
            INSERT INTO drivers(name, version, summary, prompt_md, tags, notes, created_at, updated_at)
            VALUES($1, $2, $3, $4, $5, $6, NOW(), NOW())
            ON CONFLICT (name) DO UPDATE SET
              version = EXCLUDED.version,
              summary = COALESCE(EXCLUDED.summary, drivers.summary),
              prompt_md = COALESCE(EXCLUDED.prompt_md, drivers.prompt_md),
              tags = COALESCE(EXCLUDED.tags, drivers.tags),
              notes = COALESCE(EXCLUDED.notes, drivers.notes),
              updated_at = NOW()
            RETURNING id
          SQL
        )
        res[0]['id'].to_i
      end

      def update_driver(name:, version: nil, summary: nil, prompt_md: nil, tags: nil, notes: nil)
        sets = ['updated_at = NOW()']
        params = []
        idx = 1
        unless version.nil?
          sets << "version = $#{idx}"
          params << version
          idx += 1
        end
        unless summary.nil?
          sets << "summary = $#{idx}"
          params << summary
          idx += 1
        end
        unless prompt_md.nil?
          sets << "prompt_md = $#{idx}"
          params << prompt_md
          idx += 1
        end
        unless tags.nil?
          sets << "tags = $#{idx}"
          params << text_array_encoder.encode(Array(tags))
          idx += 1
        end
        unless notes.nil?
          sets << "notes = $#{idx}"
          params << notes
          idx += 1
        end
        params << name
        sql = "UPDATE drivers SET #{sets.join(', ')} WHERE name = $#{idx} RETURNING id"
        res = exec_params(sql, params)
        res.ntuples.positive? ? res[0]['id'].to_i : nil
      end

      def get_driver_by_name(name)
        res = exec_params('SELECT * FROM drivers WHERE name=$1', [name])
        res.ntuples.positive? ? res[0] : nil
      end

      def list_drivers(filter: nil)
        if filter && !filter.to_s.strip.empty?
          q = "%#{filter}%"
          res = exec_params(
            "SELECT * FROM drivers WHERE name ILIKE $1 OR summary ILIKE $1 OR array_to_string(tags, ' ') ILIKE $1 ORDER BY name ASC",
            [q]
          )
        else
          res = exec('SELECT * FROM drivers ORDER BY name ASC')
        end
        res.to_a
      end

      def delete_driver(name)
        res = exec_params('DELETE FROM drivers WHERE name = $1 RETURNING id', [name])
        res.ntuples.positive?
      end

      # =========================
      # App CRUD: Think Workflows
      # =========================
      # NOTE: driver_version and rules have been removed from workflows.
      # Driver prompts are now managed by the Drivers engine.
      def create_think_workflow(workflow_id:, name: nil, description: nil, version: 1, steps:)
        steps_json = steps.is_a?(String) ? steps : JSON.generate(steps)
        res = exec_params(
          <<~SQL, [workflow_id, name || workflow_id, description, version, steps_json]
            INSERT INTO think_workflows(workflow_id, name, description, version, steps)
            VALUES($1, $2, $3, $4, $5::jsonb)
            ON CONFLICT (workflow_id) DO UPDATE SET
              name = COALESCE(EXCLUDED.name, think_workflows.name),
              description = COALESCE(EXCLUDED.description, think_workflows.description),
              version = EXCLUDED.version,
              steps = EXCLUDED.steps,
              updated_at = NOW()
            RETURNING id
          SQL
        )
        res[0]['id'].to_i
      end

      def update_think_workflow(workflow_id:, name: nil, description: nil, version: nil, steps: nil)
        sets = ['updated_at = NOW()']
        params = []
        idx = 1
        unless name.nil?
          sets << "name = $#{idx}"
          params << name
          idx += 1
        end
        unless description.nil?
          sets << "description = $#{idx}"
          params << description
          idx += 1
        end
        unless version.nil?
          sets << "version = $#{idx}"
          params << version
          idx += 1
        end
        unless steps.nil?
          sets << "steps = $#{idx}::jsonb"
          params << (steps.is_a?(String) ? steps : JSON.generate(steps))
          idx += 1
        end
        params << workflow_id
        sql = "UPDATE think_workflows SET #{sets.join(', ')} WHERE workflow_id = $#{idx} RETURNING id"
        res = exec_params(sql, params)
        res.ntuples.positive? ? res[0]['id'].to_i : nil
      end

      def get_think_workflow(workflow_id)
        res = exec_params('SELECT * FROM think_workflows WHERE workflow_id = $1', [workflow_id])
        return nil if res.ntuples.zero?

        row = res[0]
        row['steps'] = JSON.parse(row['steps']) if row['steps'].is_a?(String)
        row
      end

      def list_think_workflows(filter: nil)
        if filter && !filter.to_s.strip.empty?
          q = "%#{filter}%"
          res = exec_params(
            "SELECT * FROM think_workflows WHERE workflow_id ILIKE $1 OR name ILIKE $1 OR description ILIKE $1 ORDER BY workflow_id ASC",
            [q]
          )
        else
          res = exec('SELECT * FROM think_workflows ORDER BY workflow_id ASC')
        end
        res.to_a.map do |row|
          row['steps'] = JSON.parse(row['steps']) if row['steps'].is_a?(String)
          row
        end
      end

      def delete_think_workflow(workflow_id)
        res = exec_params('DELETE FROM think_workflows WHERE workflow_id = $1 RETURNING id', [workflow_id])
        res.ntuples.positive?
      end

      # =========================
      # App CRUD: Agents
      # =========================
      def create_agent(name:, persona_id: nil, driver_prompt: nil, driver_name: nil, rule_set_ids: [], favorite: false, instructions: nil, model_id: nil)
        params = [name, persona_id, driver_prompt, driver_name, int_array_encoder.encode(rule_set_ids), favorite, instructions, model_id]
        res = exec_params(
          <<~SQL, params
            INSERT INTO agents(name, persona_id, driver_prompt, driver_name, rule_set_ids, favorite, instructions, model_id, created_at, updated_at)
            VALUES($1,$2,$3,$4,$5,$6,$7,$8,NOW(),NOW())
            ON CONFLICT (name) DO UPDATE
            SET persona_id=EXCLUDED.persona_id,
                driver_prompt=COALESCE(EXCLUDED.driver_prompt, agents.driver_prompt),
                driver_name=COALESCE(EXCLUDED.driver_name, agents.driver_name),
                rule_set_ids=EXCLUDED.rule_set_ids,
                favorite=EXCLUDED.favorite,
                instructions=COALESCE(EXCLUDED.instructions, agents.instructions),
                model_id=EXCLUDED.model_id,
                updated_at=NOW()
            RETURNING id
          SQL
        )
        res[0]['id'].to_i
      end

      def get_agent(id)
        res = exec_params('SELECT * FROM agents WHERE id=$1', [id])
        res.ntuples.positive? ? res[0] : nil
      end

      def find_agent_by_name(name)
        res = exec_params('SELECT * FROM agents WHERE name=$1', [name])
        res.ntuples.positive? ? res[0] : nil
      end

      def list_agents
        res = exec('SELECT * FROM agents ORDER BY name ASC')
        res.to_a
      end

      def delete_agent_by_name(name)
        res = exec_params('SELECT id FROM agents WHERE name=$1', [name])
        return 0 if res.ntuples.zero?

        id = res[0]['id']
        exec_params('DELETE FROM agents WHERE id=$1', [id])
        1
      end

      def increment_agent_run_count(agent_id)
        exec_params('UPDATE agents SET run_count = run_count + 1, last_run_at = NOW(), updated_at = NOW() WHERE id=$1', [agent_id])
        true
      end

      def record_agent_run(agent_id:, input:, output_summary:, status:, duration_ms:, full_transcript: nil)
        payload = full_transcript.nil? ? nil : JSON.generate(full_transcript)
        res = exec_params(
          <<~SQL, [agent_id, input, output_summary, status, duration_ms, payload]
            INSERT INTO agent_runs(agent_id, input, output_summary, status, duration_ms, full_transcript)
            VALUES($1,$2,$3,$4,$5,$6)
            RETURNING id
          SQL
        )
        res[0]['id'].to_i
      end

      def list_agent_runs(agent_id, limit: 50)
        res = exec_params(
          'SELECT * FROM agent_runs WHERE agent_id=$1 ORDER BY id DESC LIMIT $2',
          [agent_id, limit]
        )
        res.to_a
      end

      # =========================
      # App CRUD: Workflows
      private

      def project_root
        base = ENV['SAVANT_PATH'] && !ENV['SAVANT_PATH'].empty? ? ENV['SAVANT_PATH'] : File.expand_path('../../..', __dir__)
        File.expand_path(base)
      end

      def default_migrations_dir
        File.join(project_root, 'db', 'migrations')
      end

      def ensure_schema_migrations!
        exec(<<~SQL)
          CREATE TABLE IF NOT EXISTS schema_migrations (
            version TEXT PRIMARY KEY,
            applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
          );
        SQL
        true
      end

      def migration_applied?(version)
        res = exec_params('SELECT 1 FROM schema_migrations WHERE version=$1', [version])
        res.ntuples.positive?
      end

      def mark_migration_applied!(version)
        exec_params('INSERT INTO schema_migrations(version) VALUES($1) ON CONFLICT (version) DO NOTHING', [version])
        true
      end

      # Establish a PG connection using, in order of precedence:
      # 1) DATABASE_URL
      # 2) Rails database.yml (when running under Rails)
      # 3) libpq env (PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABASE)
      # 4) Sensible local defaults for non‑Docker: dbname=savant on localhost:5432
      def connect!
        # 1) Explicit URL
        if @url && !@url.to_s.empty?
          begin
            return PG.connect(@url)
          rescue PG::ConnectionBad => e
            # If the DB in the URL does not exist, try to create it using the same host/port/user
            begin
              m = @url.match(%r{postgresql?://([^/]+)/([^?]+)})
              if m
                hostport = m[1]
                dbname = m[2]
                # Split host:port
                host, port = hostport.split(':', 2)
                admin_params = {}
                admin_params[:host] = host if host && !host.empty?
                admin_params[:port] = port.to_i if port
                admin_params[:dbname] = 'postgres'
                admin = PG.connect(admin_params)
                admin.exec("CREATE DATABASE \"#{dbname}\"")
                admin.close
                return PG.connect(@url)
              end
            rescue StandardError
              raise e
            end
            raise e
          end
        end

        # 2) Rails config if present
        begin
          if defined?(ActiveRecord::Base) && ActiveRecord::Base.respond_to?(:connection_db_config)
            cfg = ActiveRecord::Base.connection_db_config
            if cfg
              h = cfg.configuration_hash
              params = {}
              params[:host] = h[:host] if h[:host]
              params[:port] = h[:port] if h[:port]
              params[:dbname] = h[:database] if h[:database]
              params[:user] = h[:username] if h[:username]
              params[:password] = h[:password] if h[:password]
              return PG.connect(params) if params[:dbname]
            end
          end
        rescue StandardError
          # fall through to env/defaults
        end

        # 3) If libpq env is present, let PG pick it up
        if ENV['PGDATABASE'] || ENV['PGHOST'] || ENV['PGUSER'] || ENV['PGPASSWORD']
          begin
            return PG.connect
          rescue PG::ConnectionBad => e
            # Try to auto-create the target database if missing
            begin
              target_db = ENV['PGDATABASE'] || 'savant'
              host = ENV['PGHOST'] || 'localhost'
              port = (ENV['PGPORT'] || 5432).to_i
              admin = PG.connect(host: host, port: port, dbname: 'postgres', user: ENV['PGUSER'], password: ENV['PGPASSWORD'])
              admin.exec("CREATE DATABASE \"#{target_db}\"")
              admin.close
              return PG.connect
            rescue StandardError
              raise e
            end
          end
        end

        # 4) Sensible local default (non‑Docker): dbname per env on localhost:5432
        env = (ENV['DB_ENV'] && !ENV['DB_ENV'].empty?) ? ENV['DB_ENV'] : ((ENV['RAILS_ENV'] && !ENV['RAILS_ENV'].empty?) ? ENV['RAILS_ENV'] : (ENV['RACK_ENV'] && !ENV['RACK_ENV'].empty?) ? ENV['RACK_ENV'] : 'development')
        default_db = env.to_s == 'test' ? 'savant_test' : 'savant_development'
        params = { dbname: default_db }
        params[:host] = ENV['PGHOST'] && !ENV['PGHOST'].empty? ? ENV['PGHOST'] : 'localhost'
        params[:port] = (ENV['PGPORT'] || 5432).to_i
        params[:user] = ENV['PGUSER'] if ENV['PGUSER'] && !ENV['PGUSER'].empty?
        params[:password] = ENV['PGPASSWORD'] if ENV['PGPASSWORD'] && !ENV['PGPASSWORD'].empty?
        begin
          return PG.connect(params)
        rescue PG::ConnectionBad => e
          # Create database if missing using connection to 'postgres'
          begin
            admin_params = params.dup
            admin_params[:dbname] = 'postgres'
            admin = PG.connect(admin_params)
            admin.exec("CREATE DATABASE \"#{params[:dbname]}\"")
            admin.close
            return PG.connect(params)
          rescue StandardError
            raise e
          end
        end
      end

      def text_array_encoder
        @text_array_encoder ||= PG::TextEncoder::Array.new(
          name: 'text[]',
          elements_type: PG::TextEncoder::String.new(name: 'text')
        )
      end

      def int_array_encoder
        @int_array_encoder ||= PG::TextEncoder::Array.new(
          name: 'int[]',
          elements_type: PG::TextEncoder::Integer.new(name: 'int4')
        )
      end

      # Suppress Postgres NOTICE messages (e.g., long word warnings) unless running in debug/trace mode.
      # Controlled by LOG_LEVEL environment variable.
      def configure_client_min_messages
        lvl = (ENV['LOG_LEVEL'] || 'error').to_s.downcase
        min = %w[trace debug].include?(lvl) ? 'NOTICE' : 'WARNING'
        exec("SET client_min_messages TO #{min}")
      rescue StandardError
        # best-effort; ignore if not supported or connection not ready
        nil
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
