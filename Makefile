.PHONY: dev-ui dev-server kill-dev-server ls ps pg mongosh ui-build-local db-migrate db-fts db-smoke db-status db-drop db-create db-seed db-migrate-status db-reset

INDEXER_CMD ?= bundle exec ruby ./bin/context_repo_indexer
PG_CMD ?= psql
DB_ENV ?= development
DB_NAME ?= $(if $(filter $(DB_ENV),test),savant_test,savant_development)
DB_ENVS := development test
MONGO_DB ?= $(if $(filter $(DB_ENV),test),savant_test,savant_development)
# Increase default open files for Rails dev server to avoid EMFILE (file watcher + sockets)
OPEN_FILES ?= 8192

# Minimal dev targets with sensible defaults
export SAVANT_DEV ?= 1
export LOG_DISABLE_MONGO ?= 1
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
	  cd frontend && npm install --include=dev --legacy-peer-deps && VITE_HUB_BASE=$(HUB_BASE) npm run dev -- --host 0.0.0.0 \
	'

# Start the Rails API server only
dev-server:
	@echo "Starting Rails API on 0.0.0.0:9999..."
	@bash -lc '[ -n "$$DATABASE_URL" ] && echo "Using DATABASE_URL=$$DATABASE_URL" || echo "Using config/database.yml (no DATABASE_URL set)"'
	@bash -lc 'ulimit -n $(OPEN_FILES); echo "ulimit -n now=$$(ulimit -n)"; cd server && $(HOME)/.rbenv/shims/bundle exec rails s -b 0.0.0.0 -p 9999'

# Kill the Rails dev server
kill-dev-server:
	@echo "Stopping Rails dev server (port 9999)..."
	@bash -lc '\
	  set -e; \
	  PID_FILE=server/tmp/pids/server.pid; \
	  if [ -f "$$PID_FILE" ]; then \
	    PID=$$(cat "$$PID_FILE"); \
	    if [ -n "$$PID" ]; then \
	      echo "Sending TERM to PID $$PID..."; \
	      kill -TERM "$$PID" 2>/dev/null || true; \
	      # wait up to 5s for graceful shutdown\n\
	      for i in 1 2 3 4 5; do \
	        if kill -0 "$$PID" 2>/dev/null; then sleep 1; else break; fi; \
	      done; \
	      if kill -0 "$$PID" 2>/dev/null; then \
	        echo "Force killing PID $$PID..."; \
	        kill -KILL "$$PID" 2>/dev/null || true; \
	      fi; \
	    fi; \
	  fi; \
	  # Fallback: kill anything listening on port 9999\n\
	  PIDS=$$(lsof -ti tcp:9999 2>/dev/null | tr "\n" " "); \
	  if [ -n "$$PIDS" ]; then \
	    echo "Killing processes on :9999 => $$PIDS"; \
	    kill -TERM $$PIDS 2>/dev/null || true; \
	    sleep 1; \
	    for P in $$PIDS; do kill -0 $$P 2>/dev/null && kill -KILL $$P 2>/dev/null || true; done; \
	  fi; \
	  rm -f "$$PID_FILE"; \
	'
	@sleep 1
	@if lsof -i :9999 -sTCP:LISTEN >/dev/null 2>&1; then \
	  echo "Warning: Port 9999 still in use"; \
	else \
	  echo "Server stopped. Port 9999 is free."; \
	fi

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
	  cd frontend && npm install --include=dev --legacy-peer-deps && npm run build; \
	  rm -rf ../public/ui && mkdir -p ../public/ui && cp -R dist/* ../public/ui/ \
	'
	@echo "UI built → public/ui"

# Database tasks (non-destructive by default)
db-migrate:
	@bash -lc 'set -e; for env in $(DB_ENVS); do \
	  name=$$( [ "$$env" = test ] && echo savant_test || echo savant_development ); \
	  echo "Applying DB migrations (non-destructive, versioned) on $$name..."; \
	  DB_ENV=$$env DB_NAME=$$name PGDATABASE=$$name $(HOME)/.rbenv/shims/bundle exec ruby ./bin/db_migrate; \
	done'

db-migrate-status:
	@echo "Showing migration status for $(DB_ENV) (DB_NAME=$(DB_NAME))..."
	@cd server && RAILS_ENV=$(DB_ENV) $(HOME)/.rbenv/shims/bundle exec rails db:migrate:status

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
	@bash -lc 'set -e; for env in $(DB_ENVS); do \
	  name=$$( [ "$$env" = test ] && echo savant_test || echo savant_development ); \
	  echo "Dropping $$name (env=$$env)..."; \
	  DB_ENV=$$env DB_NAME=$$name $(HOME)/.rbenv/shims/bundle exec ruby ./bin/db_drop; \
	done'

db-create:
	@bash -lc 'set -e; for env in $(DB_ENVS); do \
	  name=$$( [ "$$env" = test ] && echo savant_test || echo savant_development ); \
	  echo "Creating $$name (env=$$env)..."; \
	  DB_ENV=$$env DB_NAME=$$name $(HOME)/.rbenv/shims/bundle exec ruby ./bin/db_create; \
	  echo "Ensuring FTS indexes on $$name..."; \
	  DB_ENV=$$env DB_NAME=$$name $(HOME)/.rbenv/shims/bundle exec ruby ./bin/db_fts; \
	done'

db-seed:
	@bash -lc 'set -e; for env in $(DB_ENVS); do \
	  name=$$( [ "$$env" = test ] && echo savant_test || echo savant_development ); \
	  echo "Seeding $$name (env=$$env)..."; \
	  DB_ENV=$$env DB_NAME=$$name $(HOME)/.rbenv/shims/bundle exec ruby ./bin/db_seed; \
	done'

db-reset: db-drop db-create db-migrate db-seed
	@echo "Database reset complete for development and test"



ls:
	@printf "Available make commands:\n";
	@$(MAKE) -pRrq | awk -F: '/^[^.#][^\t =]+:/ {print $$1}' | sort -u | grep -v '^\.PHONY$$'

ps:
	@printf "Running make processes:\n";
	@ps -ef | grep '[m]ake' | grep -v "make ps"

# Connect to PostgreSQL (local installation)
pg:
	@if [ -n "$(DATABASE_URL)" ]; then \
	  echo "Connecting via DATABASE_URL"; \
	  $(PG_CMD) "$(DATABASE_URL)"; \
	else \
	  echo "Connecting to PostgreSQL ($(DB_NAME))..."; \
	  $(PG_CMD) -h localhost -p 5432 -d $(DB_NAME); \
	fi

# Connect to MongoDB (local installation)
# Install: brew install mongodb-community
mongosh:
	@echo "Connecting to MongoDB ($(MONGO_DB))..."
	@mongosh "mongodb://localhost:27017/$(MONGO_DB)"

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

# -----------------
# Diagnostics: FD usage for Rails dev server
# -----------------
.PHONY: fd-rails
fd-rails:
	@bash -lc '\
	  PID_FILE=server/tmp/pids/server.pid; \
	  if [ ! -f "$$PID_FILE" ]; then \
	    echo "Rails server PID file not found at $$PID_FILE"; \
	    echo "Start the server with: make dev-server"; exit 1; \
	  fi; \
	  PID=$$(cat "$$PID_FILE"); \
	  if ! ps -p $$PID >/dev/null 2>&1; then \
	    echo "Rails server not running (PID $$PID)"; exit 1; \
	  fi; \
	  echo "Analyzing FD usage for Rails PID $$PID"; \
	  if ! command -v lsof >/dev/null 2>&1; then \
	    echo "lsof is required (brew install lsof)"; exit 127; \
	  fi; \
	  TOTAL=$$(lsof -p $$PID 2>/dev/null | wc -l | awk "{print $$1}"); \
	  echo "- total FDs: $$TOTAL"; \
	  echo "- by TYPE:"; \
	  lsof -p $$PID 2>/dev/null | awk 'NR>1{print $$5}' | sort | uniq -c | sort -nr | head -n 10; \
	  echo "- top file paths (REG/DIR):"; \
	  lsof -p $$PID 2>/dev/null | awk 'NR>1 && ($$5=="REG"||$$5=="DIR"){print $$9}' | sed "/^$$/d" | sort | uniq -c | sort -nr | head -n 20; \
	'

# -----------------
# Reasoning API (Python)
# -----------------
.PHONY: reasoning-setup reasoning-api reasoning-api-stdout reasoning-api-file
reasoning-setup:
	python3 -m venv .venv_reasoning && . .venv_reasoning/bin/activate && python3 -m pip install -r reasoning/requirements.txt

reasoning-api:
	./scripts/run_reasoning_api.sh

# Run Reasoning API with stdout logging enabled
reasoning-api-stdout:
	REASONING_LOG_STDOUT=1 ./scripts/run_reasoning_api.sh

# Run Reasoning API with file logging (override path: make reasoning-api-file log=logs/reasoning.log)
reasoning-api-file:
	@bash -lc '\
	  LOG_PATH="$${log:-logs/reasoning.log}"; \
	  echo "Writing reasoning logs to $$LOG_PATH"; \
	  REASONING_LOG_FILE="$$LOG_PATH" ./scripts/run_reasoning_api.sh \
	'

# Run Reasoning queue worker only (no HTTP)
.PHONY: reasoning-worker
reasoning-worker:
	./scripts/run_reasoning_worker.sh

.PHONY: reasoning-queue-status
reasoning-queue-status:
	./scripts/reasoning_queue_status.sh

.PHONY: mongo-logs-drop
mongo-logs-drop:
	./scripts/mongo_drop_logs.sh

.PHONY: mongo-logs-drop-reasoning
mongo-logs-drop-reasoning:
	REASONING_ONLY=1 ./scripts/mongo_drop_logs.sh
