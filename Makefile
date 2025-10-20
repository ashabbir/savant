.PHONY: dev logs down ps migrate fts smoke mcp-test jira-test jira-self test \
  repo-index-all repo-index-repo repo-delete-all repo-delete-repo repo-status

# Ensure rbenv shims take precedence in Make subshells
# (Reverted) Do not globally override PATH; use explicit rbenv shim per target.

dev:
	@docker compose up -d

logs:
	@docker compose logs -f indexer-ruby postgres

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

test:
	@sh -lc 'if command -v bundle >/dev/null 2>&1; then bundle exec rspec; \
  elif [ -x "$$HOME/.rbenv/shims/bundle" ]; then "$$HOME/.rbenv/shims/bundle" exec rspec; \
  else rspec; fi'

 
