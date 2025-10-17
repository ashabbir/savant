.PHONY: dev logs down ps migrate fts smoke index-all index-repo mcp status mcp-test

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

mcp:
	@docker compose up -d mcp-ruby

status:
	@docker compose exec -T indexer-ruby ./bin/status

# Usage: make mcp-test q='User' limit=5 repo=crawler
mcp-test:
	@docker compose exec -T mcp-ruby sh -lc 'Q="$(q)"; R="$(repo)"; L="$(limit)"; [ -n "$$Q" ] || Q="User"; [ -n "$$L" ] || L=5; if [ -n "$$R" ]; then RJSON="\"$$R\""; else RJSON=null; fi; \
	  printf "{\"tool\":\"search\",\"q\":\"%s\",\"repo\":%s,\"limit\":%s}\n" "$$Q" "$$RJSON" "$$L" | ruby ./bin/mcp_server'
