.PHONY: dev up logs logs-all down ps migrate fts smoke mcp-test jira-test jira-self \
  repo-index-all repo-index-repo repo-delete-all repo-delete-repo repo-status \
  demo-engine demo-run demo-call hub hub-logs hub-down hub-local hub-local-logs ls \
  ui-build ui-install ui-dev dev-ui ui-open frontend-stop

# Ensure rbenv shims take precedence in Make subshells
# (Reverted) Do not globally override PATH; use explicit rbenv shim per target.

dev:
	@docker compose up -d --remove-orphans
	@$(MAKE) ui-build
	@docker compose stop frontend || true
	@docker compose rm -f -s -v frontend || true
	@echo ""
	@echo "========================================="
	@echo "  Savant is ready!"
	@echo "  UI:  http://localhost:9999/ui"
	@echo "  Hub: http://localhost:9999"
	@echo "========================================="

up: dev

logs:
	@docker compose logs -f indexer-ruby postgres

logs-all:
	@docker compose logs -f postgres hub frontend

down:
	@docker compose down -v

ps:
	@docker compose ps

migrate:
	@docker compose exec -T indexer-ruby ./bin/db_migrate || true

fts:
	@docker compose exec -T indexer-ruby ./bin/db_fts || true

smoke:
	@docker compose exec -T indexer-ruby ./bin/db_smoke || true

# Context Repo Indexer (under Context engine)
repo-index-all:
	@mkdir -p logs
	@docker compose exec -T indexer-ruby ./bin/context_repo_indexer index all 2>&1 | tee -a logs/context_repo_indexer.log

repo-index-repo:
	@test -n "$(repo)" || (echo "usage: make repo-index-repo repo=<name>" && exit 2)
	@mkdir -p logs
	@docker compose exec -T indexer-ruby ./bin/context_repo_indexer index $(repo) 2>&1 | tee -a logs/context_repo_indexer.log

repo-delete-all:
	@docker compose exec -T indexer-ruby ./bin/context_repo_indexer delete all

repo-delete-repo:
	@test -n "$(repo)" || (echo "usage: make repo-delete-repo repo=<name>" && exit 2)
	@docker compose exec -T indexer-ruby ./bin/context_repo_indexer delete $(repo)

repo-status:
	@docker compose exec -T indexer-ruby ./bin/context_repo_indexer status

# Convenience targets for PRD frontend/backend flow
reindex-all:
	@$(MAKE) repo-delete-all || true
	@$(MAKE) repo-index-all

index-repo:
	@$(MAKE) repo-index-repo repo=$(repo)

delete-repo:
	@$(MAKE) repo-delete-repo repo=$(repo)

# Build static UI and serve under Hub at /ui
ui-build:
	@docker compose run --rm -T frontend /bin/sh -lc 'cd /app/frontend && (npm ci || npm install --include=dev) && npm run build -- --base=/ui/ && rm -rf /app/public/ui && mkdir -p /app/public/ui && cp -r dist/* /app/public/ui/'

# Install frontend dependencies only (no build)
ui-install:
	@docker compose run --rm -T frontend /bin/sh -lc 'cd /app/frontend && npm install --include=dev'

# Run frontend dev server (hot reload) - requires hub running
ui-dev:
	@docker compose run --rm -p 5173:5173 frontend /bin/sh -lc 'cd /app/frontend && npm install --include=dev && npm run dev -- --host 0.0.0.0'

# Start hub + frontend dev server together (hot reload)
dev-ui:
	@docker compose up -d postgres hub
	@echo "Hub starting at http://localhost:9999"
	@echo "Starting frontend dev server with hot reload..."
	@docker compose run --rm -p 5173:5173 frontend /bin/sh -lc 'cd /app/frontend && npm install --include=dev && npm run dev -- --host 0.0.0.0'

ui-open:
	@echo "Open: http://localhost:9999/ui"

frontend-stop:
	@docker compose stop frontend || true

# Hub service
hub:
	@docker compose up -d hub

hub-logs:
	@docker compose logs -f hub

hub-down:
	@docker compose stop hub

# Usage: make mcp-test q='User' limit=5 repo=crawler
mcp-test:
	@sh -lc 'Q="$(q)"; R="$(repo)"; L="$(limit)"; [ -n "$$Q" ] || Q="User"; [ -n "$$L" ] || L=5; if [ -n "$$R" ]; then RJSON="\"$$R\""; else RJSON=null; fi; \
	  printf "{\"tool\":\"fts/search\",\"q\":\"%s\",\"repo\":%s,\"limit\":%s}\n" "$$Q" "$$RJSON" "$$L" | SAVANT_PATH=$(PWD) DATABASE_URL=postgres://context:contextpw@localhost:5433/contextdb $(HOME)/.rbenv/shims/bundle exec ruby ./bin/mcp_server'

# Usage: make jira-test jql='project = ABC order by updated desc' limit=5
jira-test:
	@sh -lc 'JQL="$(jql)"; L="$(limit)"; [ -n "$$JQL" ] || { echo "usage: make jira-test jql=... [limit=10]"; exit 2; }; [ -n "$$L" ] || L=10; \
	  printf "{\"tool\":\"jira_search\",\"jql\":\"%s\",\"limit\":%s}\n" "$$JQL" "$$L" | SAVANT_PATH=$(PWD) $(HOME)/.rbenv/shims/bundle exec ruby ./bin/mcp_server'

# Quick auth check for Jira credentials
jira-self:
	@sh -lc 'printf "{\"tool\":\"jira_self\"}\n" | SAVANT_PATH=$(PWD) $(HOME)/.rbenv/shims/bundle exec ruby ./bin/mcp_server'

# Demo engine helpers
demo-engine:
	@ruby ./bin/savant generate engine demo --with-db --force || true

demo-run:
	@MCP_SERVICE=demo ruby ./bin/mcp_server

demo-call:
	@ruby ./bin/savant call 'demo/hello' --service=demo --input='{"name":"dev"}'

# Run Hub locally (no Docker)
hub-local:
	@SAVANT_PATH=$(PWD) $(HOME)/.rbenv/shims/bundle exec ruby ./bin/savant hub

hub-local-logs:
	@tail -f /tmp/savant/hub.log

ls:
	@awk -F':' '/^[[:alnum:]_.-]+:([^=]|$$)/ {print $$1}' $(MAKEFILE_LIST) | grep -v '^\.' | sort -u
