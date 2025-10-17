.PHONY: dev logs down ps

dev:
	@docker compose up -d

logs:
	@docker compose logs -f indexer-ruby mcp-ruby

down:
	@docker compose down -v

ps:
	@docker compose ps

