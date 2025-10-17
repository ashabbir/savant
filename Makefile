.PHONY: dev logs down ps migrate fts smoke index-all index-repo mcp

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
	@docker compose exec -T indexer-ruby ./bin/index all | tee logs/indexer.log || true

index-repo:
	@test -n "$(repo)" || (echo "usage: make index-repo repo=<name>" && exit 2)
	@mkdir -p logs
	@docker compose exec -T indexer-ruby ./bin/index $(repo) | tee logs/indexer.log || true

mcp:
	@docker compose up -d mcp-ruby
