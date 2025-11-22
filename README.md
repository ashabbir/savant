# Savant

Savant is a lightweight Ruby toolkit for running local MCP services such as fast code search (Context) and Jira access. This README stays focused on how to get a workstation ready, index repos, and launch a server. All deep dives now live in the **Memory Bank** (see below).

## Table of Contents
1. [Before You Begin](#before-you-begin)
2. [Get Started](#get-started)
3. [Run Options](#run-options)
4. [Helpful Commands](#helpful-commands)
5. [Memory Bank (Canonical Docs)](#memory-bank-canonical-docs)
6. [Need Help?](#need-help)

## Before You Begin
- **Ruby & Bundler:** use the Ruby version declared in `Gemfile` (3.2+ recommended) and run `bundle install`.
- **Postgres:** host install or Docker container. Configure via `DATABASE_URL` or `config/settings.json`.
- **Make, Git, Docker (optional):** helper commands expect these.
- **Repos to index:** ensure the paths you configure are readable inside your terminal or Docker container.

## Get Started
1. **Install gems**
   ```bash
   bundle install
   ```
2. **Create your config**
   ```bash
   cp config/settings.example.json config/settings.json
   # edit repos, database credentials, and MCP options
   ```
3. **Boot Postgres**
   - Host DB: start the service locally and confirm the credentials in your config.
   - Docker option: `docker compose up -d postgres` or run `make dev` to bring up Postgres + helper volumes.
4. **Prepare the database (Context engine)**
   ```bash
   make migrate
   make fts
   ```
5. **Index repos (Context engine)**
   ```bash
   make repo-index-all
   # or: make repo-index-repo repo=<name>
   ```
6. **Launch an MCP service**
   ```bash
   # Context code search
   MCP_SERVICE=context bundle exec ruby ./bin/mcp_server

   # Jira tools (requires JIRA_* env or config)
   MCP_SERVICE=jira bundle exec ruby ./bin/mcp_server
   ```
   Set `SAVANT_PATH` if you run the server outside this repository root so it can locate `config/` and `logs/`.
7. **Connect from your editor or agent**
   - Point Claude Code, Cline, or another MCP client at `ruby ./bin/mcp_server` with `MCP_SERVICE` set as needed.
   - Use `make mcp-test q='term'` to sanity-check the Context engine before wiring it into an editor.

## Run Options
Choose a style that matches your setup—swap between them as needed.

### Raw host (manual control)
- Use your local Ruby, Postgres, and `bundle exec` commands directly.
- Start Postgres however you prefer (brew service, systemd, psql app, etc.).
- Run `bundle exec ruby ./bin/mcp_server` with the desired `MCP_SERVICE` value.
- Great when you want maximum transparency into processes and logs.

### Make helpers (recommended)
- The Make targets shell out to Docker Compose for Postgres so you get containerized infra without writing `docker` commands yourself.
- `make dev` – launches Postgres (Docker) plus convenience volumes; you still run Ruby processes on the host.
- `make repo-index-all`, `make repo-index-repo repo=<name>` – wrap the indexer for consistent flags.
- `make migrate`, `make fts`, `make repo-status` – manage DB schema and indexed data.
- Ideal when you want Docker-managed Postgres but prefer to run Ruby CLIs on your machine.

### Full Docker / Compose services
- Run everything (Postgres + MCP services) inside containers when you want full isolation.
- `docker compose build` – build images (Ruby services + Postgres).
- `make dev` or `docker compose up -d postgres` – start Postgres and share volumes for repos/logs.
- `docker compose run --rm -T mcp-context` – run the Context MCP entirely in a container (same for Jira via `mcp-jira`).
- Helpful for reproducing a uniform environment or running Savant without installing Ruby locally.

## Helpful Commands
- `bin/context_repo_indexer status` – inspect repo counts and mtimes.
- `make repo-status` – quick status summary for all repos.
- `make repo-delete-repo repo=<name>` – drop stored data for one repo.
- `bin/savant list tools --service=<context|jira>` – inspect tool registries.
- `bin/savant call '<tool>' --service=<...> --input='{}'` – dry-run a tool without an editor.
- `bin/config_validate` – confirm that `config/settings.json` matches the schema.
- `git status && git add <files>` – stage changes before sharing.
- `git commit -m "Describe change" && git push origin <branch>` – capture and publish your work (use branch naming conventions in your org).

## Memory Bank (Canonical Docs)
Detailed architecture notes, engine internals, and integration walkthroughs now live exclusively in the `memory_bank/` directory:
- [memory_bank/architecture.md](memory_bank/architecture.md) – system overview, data model, and flows.
- [memory_bank/framework.md](memory_bank/framework.md) – MCP core, transport, logging, and configuration internals.
- [memory_bank/framework.md#engine-scaffolding](memory_bank/framework.md#engine-scaffolding) – generator + scaffolding flow for building new engines.
- [memory_bank/engine_context.md](memory_bank/engine_context.md) – indexer, chunking, languages, and search behavior.
- [memory_bank/engine_jira.md](memory_bank/engine_jira.md) – Jira client, tools, authentication, and CLI helpers.

If you come across older READMEs scattered throughout the repo, treat them as historical references only—the Memory Bank files above are the single source of truth for technical documentation.

## Need Help?
- Tail `logs/<service>.log` (or stdout) for slow operations and stack traces.
- Reset everything with `make down && make migrate && make fts` before a clean re-index.
- Use `make repo-delete-all` to wipe indexed data if repo paths or DB credentials change.
- Reach out in your preferred channel with questions and include the relevant log snippet.

Happy indexing! When you’re ready for deeper context, head straight to the Memory Bank.
