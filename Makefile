.PHONY: dev-ui dev-server ls ps pg ui-build-local db-migrate db-fts db-smoke db-status db-drop db-create db-seed db-drop-all db-create-all db-migrate-all db-reset

INDEXER_CMD ?= bundle exec ruby ./bin/context_repo_indexer
PG_CMD ?= psql
DB_ENV ?= development
DB_NAME ?= $(if $(filter $(DB_ENV),test),savant_test,savant_development)
DB_ENVS := development test

# Minimal dev targets with sensible defaults
export SAVANT_DEV ?= 1
HUB_BASE ?= http://localhost:9999

# Start the frontend dev server (Vite)
dev-ui:
	@echo "Starting frontend dev server (Vite) with hot reload..."
	@echo "API:    $(HUB_BASE)"
	@echo "UI:     http://localhost:5173"
	@bash -lc ' \
	  if command -v npm >/dev/null 2>&1; then :; \
	  elif [ -s "$$NVM_DIR/nvm.sh" ]; then . "$$NVM_DIR/nvm.sh"; \
	  elif [ -s "$$HOME/.nvm/nvm.sh" ]; then . "$$HOME/.nvm/nvm.sh"; \
	  fi; \
	  if ! command -v npm >/dev/null 2>&1; then \
	    echo "npm not found. Install Node (e.g., brew install node) or load nvm"; exit 127; \
	  fi; \
	  cd frontend && (npm ci || npm install --include=dev) && VITE_HUB_BASE=$(HUB_BASE) npm run dev -- --host 0.0.0.0 \
	'

# Start the Rails API server only
dev-server:
	@echo "Starting Rails API on 0.0.0.0:9999..."
	@bash -lc '[ -n "$$DATABASE_URL" ] && echo "Using DATABASE_URL=$$DATABASE_URL" || echo "Using config/database.yml (no DATABASE_URL set)"'
	@cd server && $(HOME)/.rbenv/shims/bundle exec rails s -b 0.0.0.0 -p 9999

# Build the frontend and copy to public/ui for Rails/Hub to serve
ui-build-local:
	@echo "Building frontend and staging to public/ui..."
	@bash -lc ' \
	  if command -v npm >/dev/null 2>&1; then :; \
	  elif [ -s "$$NVM_DIR/nvm.sh" ]; then . "$$NVM_DIR/nvm.sh"; \
	  elif [ -s "$$HOME/.nvm/nvm.sh" ]; then . "$$HOME/.nvm/nvm.sh"; \
	  fi; \
	  if ! command -v npm >/dev/null 2>&1; then \
	    echo "npm not found. Install Node (e.g., brew install node) or load nvm"; exit 127; \
	  fi; \
	  cd frontend && (npm ci || npm install --include=dev) && npm run build; \
	  rm -rf ../public/ui && mkdir -p ../public/ui && cp -R dist/* ../public/ui/ \
	'
	@echo "UI built → public/ui"

# Database tasks (non-destructive by default)
db-migrate:
	@echo "Applying DB migrations (non-destructive, versioned)..."
	@DB_NAME=$(DB_NAME) PGDATABASE=$(DB_NAME) $(HOME)/.rbenv/shims/bundle exec ruby ./bin/db_migrate

db-fts:
	@echo "Ensuring FTS index on chunks.chunk_text..."
	@$(HOME)/.rbenv/shims/bundle exec ruby ./bin/db_fts

db-smoke:
	@echo "Running DB smoke check (connect + migrations + FTS)..."
	@DB_NAME=$(DB_NAME) PGDATABASE=$(DB_NAME) $(HOME)/.rbenv/shims/bundle exec ruby ./bin/db_smoke

db-status:
	@echo "DB status via psql (override with PGHOST/PGPORT/PGUSER/PGPASSWORD)"
	@$(PG_CMD) -lqt 2>/dev/null | awk '{print $$1}' | sed '/^$$/d' || true

db-drop:
	@echo "Dropping database $(DB_NAME) (env=$(DB_ENV))..."
	@DB_ENV=$(DB_ENV) DB_NAME=$(DB_NAME) $(HOME)/.rbenv/shims/bundle exec ruby ./bin/db_drop

db-create:
	@echo "Creating database $(DB_NAME) (env=$(DB_ENV))..."
	@DB_ENV=$(DB_ENV) DB_NAME=$(DB_NAME) $(HOME)/.rbenv/shims/bundle exec ruby ./bin/db_create

db-seed:
	@echo "Seeding database $(DB_NAME) (env=$(DB_ENV))..."
	@DB_ENV=$(DB_ENV) DB_NAME=$(DB_NAME) $(HOME)/.rbenv/shims/bundle exec ruby ./bin/db_seed

db-drop-all:
	@bash -lc 'set -e; for env in $(DB_ENVS); do \
	  name=$$( [ "$$env" = test ] && echo savant_test || echo savant_development ); \
	  echo "Dropping $$name (env=$$env)..."; \
	  DB_ENV=$$env DB_NAME=$$name $(HOME)/.rbenv/shims/bundle exec ruby ./bin/db_drop; \
	done'

db-create-all:
	@bash -lc 'set -e; for env in $(DB_ENVS); do \
	  name=$$( [ "$$env" = test ] && echo savant_test || echo savant_development ); \
	  echo "Creating $$name (env=$$env)..."; \
	  DB_ENV=$$env DB_NAME=$$name $(HOME)/.rbenv/shims/bundle exec ruby ./bin/db_create; \
	done'

db-migrate-all:
    @bash -lc 'set -e; for env in $(DB_ENVS); do \
      name=$$( [ "$$env" = test ] && echo savant_test || echo savant_development ); \
      echo "Migrating $$name (env=$$env)..."; \
      DB_ENV=$$env DB_NAME=$$name PGDATABASE=$$name $(HOME)/.rbenv/shims/bundle exec ruby ./bin/db_migrate; \
    done'

db-seed-all:
    @bash -lc 'set -e; for env in $(DB_ENVS); do \
      name=$$( [ "$$env" = test ] && echo savant_test || echo savant_development ); \
      echo "Seeding $$name (env=$$env)..."; \
      DB_ENV=$$env DB_NAME=$$name $(HOME)/.rbenv/shims/bundle exec ruby ./bin/db_seed; \
    done'

db-setup-all: db-create-all db-migrate-all db-seed-all

db-reset: db-drop-all db-create-all db-migrate-all
	@echo "Reset complete for development and test"

ls:
	@printf "Available make commands:\n";
	@$(MAKE) -pRrq | awk -F: '/^[^.#][^\t =]+:/ {print $$1}' | sort -u | grep -v '^\.PHONY$$'

ps:
	@printf "Running make processes:\n";
	@ps -ef | grep '[m]ake' | grep -v "make ps"

pg:
	@if [ -n "$(DATABASE_URL)" ]; then \
	  echo "Connecting via DATABASE_URL"; \
	  $(PG_CMD) "$(DATABASE_URL)"; \
	else \
		  config_env=$$(ruby -rjson -e 'path = File.join("config", "settings.json"); if File.exist?(path); settings = JSON.parse(File.read(path)); db = settings["database"]; if db; env = []; host = (db["host"] || "").to_s; host = "localhost" if host.empty? || host == "postgres"; env << "PGHOST=#{host}"; env << "PGPORT=#{db["port"]}" if db["port"]; # ignore user/password from settings to avoid missing roles on local
		  env << "PGDATABASE=#{db["db"] || "$(DB_NAME)"}"; print env.join(" "); end; end'); \
	  if [ -n "$$config_env" ]; then \
	    echo "Connecting via config/settings.json"; \
	    env $$config_env $(PG_CMD); \
	  else \
	    echo "Connecting via default psql settings"; \
		    $(PG_CMD) -h localhost -p 5432 -d $(DB_NAME); \
	  fi; \
	fi

.PHONY: repo-index repo-delete repo-index-all repo-delete-all repo-reindex-all repo-status

repo-index:
	@if [ -z "$(repo)" ]; then \
	  echo "Usage: make repo-index repo=<name>"; exit 1; \
	fi
	$(INDEXER_CMD) index $(repo)

repo-delete:
	@if [ -z "$(repo)" ]; then \
	  echo "Usage: make repo-delete repo=<name>"; exit 1; \
	fi
	$(INDEXER_CMD) delete $(repo)

repo-index-all:
	$(INDEXER_CMD) index all

repo-delete-all:
	$(INDEXER_CMD) delete all

repo-reindex-all: repo-delete-all repo-index-all
	@echo "Reindexed all configured repos"

repo-status:
	$(INDEXER_CMD) status
