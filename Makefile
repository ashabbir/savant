.PHONY: dev logs down ps migrate fts smoke index-all index-repo mcp status mcp-test jira-test mcp-run mcp-context mcp-context-run mcp-jira mcp-jira-run delete-all delete-repo

dev:
	@docker compose up -d

logs:
	@docker compose logs -f indexer-ruby mcp-ruby

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

index-all:
	@mkdir -p logs
	@docker compose exec -T indexer-ruby ./bin/index all 2>&1 | tee -a logs/indexer.log

index-repo:
	@test -n "$(repo)" || (echo "usage: make index-repo repo=<name>" && exit 2)
	@mkdir -p logs
	@docker compose exec -T indexer-ruby ./bin/index $(repo) 2>&1 | tee -a logs/indexer.log

# Delete all indexed data
delete-all:
	@docker compose exec -T indexer-ruby ./bin/index delete all

# Delete a single repo's indexed data
delete-repo:
	@test -n "$(repo)" || (echo "usage: make delete-repo repo=<name>" && exit 2)
	@docker compose exec -T indexer-ruby ./bin/index delete $(repo)

mcp:
	@docker compose up -d mcp-context mcp-jira

status:
	@docker compose exec -T indexer-ruby ./bin/status

# Usage: make mcp-test q='User' limit=5 repo=crawler
mcp-test:
	@docker compose exec -T mcp-context sh -lc 'Q="$(q)"; R="$(repo)"; L="$(limit)"; [ -n "$$Q" ] || Q="User"; [ -n "$$L" ] || L=5; if [ -n "$$R" ]; then RJSON="\"$$R\""; else RJSON=null; fi; \
	  printf "{\"tool\":\"search\",\"q\":\"%s\",\"repo\":%s,\"limit\":%s}\n" "$$Q" "$$RJSON" "$$L" | ruby ./bin/mcp_server'

# Usage: make jira-test jql='project = ABC order by updated desc' limit=5
jira-test:
	@docker compose exec -T mcp-jira sh -lc 'JQL="$(jql)"; L="$(limit)"; [ -n "$$JQL" ] || { echo "usage: make jira-test jql=... [limit=10]"; exit 2; }; [ -n "$$L" ] || L=10; \
	  printf "{\"tool\":\"jira_search\",\"jql\":\"%s\",\"limit\":%s}\n" "$$JQL" "$$L" | ruby ./bin/mcp_server'

# Quick auth check for Jira credentials
jira-self:
	@docker compose exec -T mcp-jira sh -lc 'printf "{\"tool\":\"jira_self\"}\n" | ruby ./bin/mcp_server'

# Context MCP (background)
mcp-context:
	@docker compose up -d mcp-context

# Context MCP (foreground, debug)
mcp-context-run:
	@docker compose run --rm -e MCP_SERVICE=context -e LOG_LEVEL=debug -p 8765:8765 mcp-context ruby ./bin/mcp_server

# Jira MCP (background)
mcp-jira:
	@docker compose up -d mcp-jira

# Jira MCP (foreground, debug)
mcp-jira-run:
	@docker compose run --rm -e MCP_SERVICE=jira -e LOG_LEVEL=debug -p 8766:8766 mcp-jira ruby ./bin/mcp_server
