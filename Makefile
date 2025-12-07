.PHONY: dev-ui dev-server ls ps pg ui-build-local

INDEXER_CMD ?= bundle exec ruby ./bin/context_repo_indexer
PG_CMD ?= psql

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
	  echo "Connecting via default psql settings"; \
	  $(PG_CMD); \
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
