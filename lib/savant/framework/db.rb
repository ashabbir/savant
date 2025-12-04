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
        @conn = PG.connect(@url)
        configure_client_min_messages
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
        @conn = PG.connect(@url)
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

      # Drop and recreate all schema tables and indexes.
      # @return [true]
      def migrate_tables
        # Destructive reset: drop and recreate all tables/indexes
        # App tables (agents/workflows/personas/rules):
        exec('DROP TABLE IF EXISTS workflow_runs CASCADE')
        exec('DROP TABLE IF EXISTS workflow_steps CASCADE')
        exec('DROP TABLE IF EXISTS workflows CASCADE')
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

        # App schema — agents/personas/rules/workflows
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

        exec(<<~SQL)
          CREATE TABLE workflows (
            id SERIAL PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            description TEXT,
            graph JSONB,
            favorite BOOLEAN NOT NULL DEFAULT FALSE,
            run_count INTEGER NOT NULL DEFAULT 0,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
          );
        SQL

        exec(<<~SQL)
          CREATE TABLE workflow_steps (
            id SERIAL PRIMARY KEY,
            workflow_id INTEGER NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            step_type TEXT NOT NULL,
            config JSONB,
            position INTEGER
          );
        SQL
        exec('CREATE INDEX idx_workflow_steps_workflow ON workflow_steps(workflow_id)')

        exec(<<~SQL)
          CREATE TABLE workflow_runs (
            id SERIAL PRIMARY KEY,
            workflow_id INTEGER NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
            input TEXT,
            output TEXT,
            status TEXT,
            duration_ms BIGINT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            transcript JSONB
          );
        SQL
        exec('CREATE INDEX idx_workflow_runs_workflow ON workflow_runs(workflow_id)')
        true
      end

      # Ensure the GIN FTS index on `chunks.chunk_text` exists.
      # @return [true]
      def ensure_fts
        exec(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_chunks_fts ON chunks USING GIN (to_tsvector('english', chunk_text));
        SQL
        true
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
        res = exec_params('SELECT id FROM repos WHERE name=$1', [name])
        return res[0]['id'].to_i if res.ntuples.positive?

        res = exec_params('INSERT INTO repos(name, root_path) VALUES($1,$2) RETURNING id', [name, root])
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
      # App CRUD: Personas
      # =========================
      def create_persona(name, content)
        res = exec_params(
          'INSERT INTO personas(name, content) VALUES($1,$2) ON CONFLICT (name) DO UPDATE SET content=EXCLUDED.content RETURNING id',
          [name, content]
        )
        res[0]['id'].to_i
      end

      def get_persona_by_name(name)
        res = exec_params('SELECT * FROM personas WHERE name=$1', [name])
        res.ntuples.positive? ? res[0] : nil
      end

      def list_personas
        res = exec('SELECT * FROM personas ORDER BY name ASC')
        res.to_a
      end

      # =========================
      # App CRUD: Rulesets
      # =========================
      def create_ruleset(name, content)
        res = exec_params(
          'INSERT INTO rulesets(name, content) VALUES($1,$2) ON CONFLICT (name) DO UPDATE SET content=EXCLUDED.content RETURNING id',
          [name, content]
        )
        res[0]['id'].to_i
      end

      def get_ruleset_by_name(name)
        res = exec_params('SELECT * FROM rulesets WHERE name=$1', [name])
        res.ntuples.positive? ? res[0] : nil
      end

      def list_rulesets
        res = exec('SELECT * FROM rulesets ORDER BY name ASC')
        res.to_a
      end

      # =========================
      # App CRUD: Agents
      # =========================
      def create_agent(name:, persona_id: nil, driver_prompt: nil, rule_set_ids: [], favorite: false)
        params = [name, persona_id, driver_prompt, int_array_encoder.encode(rule_set_ids), favorite]
        res = exec_params(
          <<~SQL, params
            INSERT INTO agents(name, persona_id, driver_prompt, rule_set_ids, favorite)
            VALUES($1,$2,$3,$4,$5)
            ON CONFLICT (name) DO UPDATE
            SET persona_id=EXCLUDED.persona_id, driver_prompt=EXCLUDED.driver_prompt,
                rule_set_ids=EXCLUDED.rule_set_ids, favorite=EXCLUDED.favorite, updated_at=NOW()
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
      # =========================
      def create_workflow(name:, description: nil, graph: nil, favorite: false)
        graph_json = graph.nil? ? nil : JSON.generate(graph)
        res = exec_params(
          <<~SQL, [name, description, graph_json, favorite]
            INSERT INTO workflows(name, description, graph, favorite)
            VALUES($1,$2,$3::jsonb,$4)
            ON CONFLICT (name) DO NOTHING
            RETURNING id
          SQL
        )
        if res.ntuples.zero?
          # already exists; fetch id
          got = exec_params('SELECT id FROM workflows WHERE name=$1', [name])
          got[0]['id'].to_i
        else
          res[0]['id'].to_i
        end
      end

      def update_workflow(id:, description: nil, graph: nil, favorite: nil, run_count_delta: 0)
        sets = []
        params = []
        idx = 1
        unless description.nil?
          sets << "description=$#{idx}"; params << description; idx += 1
        end
        unless graph.nil?
          sets << "graph=$#{idx}::jsonb"; params << JSON.generate(graph); idx += 1
        end
        unless favorite.nil?
          sets << "favorite=$#{idx}"; params << (favorite ? true : false); idx += 1
        end
        unless run_count_delta.to_i.zero?
          sets << "run_count=run_count + #{run_count_delta.to_i}"
        end
        sets << 'updated_at=NOW()'
        params << id
        sql = "UPDATE workflows SET #{sets.join(', ')} WHERE id=$#{idx}"
        exec_params(sql, params)
        true
      end

      def get_workflow(id)
        res = exec_params('SELECT * FROM workflows WHERE id=$1', [id])
        res.ntuples.positive? ? res[0] : nil
      end

      def find_workflow_by_name(name)
        res = exec_params('SELECT * FROM workflows WHERE name=$1', [name])
        res.ntuples.positive? ? res[0] : nil
      end

      def list_workflows
        res = exec('SELECT * FROM workflows ORDER BY name ASC')
        res.to_a
      end

      def add_workflow_step(workflow_id:, name:, step_type:, config: nil, position: nil)
        cfg = config.nil? ? nil : JSON.generate(config)
        res = exec_params(
          <<~SQL, [workflow_id, name, step_type, cfg, position]
            INSERT INTO workflow_steps(workflow_id, name, step_type, config, position)
            VALUES($1,$2,$3,$4::jsonb,$5)
            RETURNING id
          SQL
        )
        res[0]['id'].to_i
      end

      def list_workflow_steps(workflow_id)
        res = exec_params('SELECT * FROM workflow_steps WHERE workflow_id=$1 ORDER BY position NULLS LAST, id ASC', [workflow_id])
        res.to_a
      end

      def record_workflow_run(workflow_id:, input:, output:, status:, duration_ms:, transcript: nil)
        payload = transcript.nil? ? nil : JSON.generate(transcript)
        res = exec_params(
          <<~SQL, [workflow_id, input, output, status, duration_ms, payload]
            INSERT INTO workflow_runs(workflow_id, input, output, status, duration_ms, transcript)
            VALUES($1,$2,$3,$4,$5,$6)
            RETURNING id
          SQL
        )
        res[0]['id'].to_i
      end

      def list_workflow_runs(workflow_id, limit: 50)
        res = exec_params('SELECT * FROM workflow_runs WHERE workflow_id=$1 ORDER BY id DESC LIMIT $2', [workflow_id, limit])
        res.to_a
      end

      private

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
