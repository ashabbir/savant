# React SPA + Savant Backend PRD

## Purpose
- Build a React (MUI) single‑page app that queries the Savant code context backend and provides repo status and admin actions.
- Provide one‑command local run via Docker Compose (frontend, backend HTTP bridge, Postgres, indexer) and Make targets including a reset+reindex workflow.

## Goals
- Launch a SPA that calls backend APIs to:
  - Perform full‑text search over indexed chunks.
  - Show per‑repo status and counts.
  - Trigger admin actions (reset cache + index all, index single repo, delete all or single repo).
- Ship a single `make up` to run everything via Docker Compose.
- Provide `make reindex-all` to reset and reindex all repos.

## Users
- Local developers who want fast, private search across their repos.

## Platforms
- Desktop web (latest Chrome/Firefox/Safari/Edge).

## User Stories
- Search
  - As a user, I can enter a query and see ranked results across indexed repos, including file path, language, snippet, and score.
  - I can filter by repo and language and paginate results.
- Repo Status
  - I can see configured repos with counts (files, blobs, chunks) and last index time.
- Admin
  - I can trigger “reset cache + index all repos”.
  - I can index a single repo.
  - I can delete all data or a single repo with confirmation.
- Feedback
  - I see loading states and errors for all actions.
  - I can view backend health status.

## Scope (v1)
- React + Vite + TypeScript + MUI 6.
- Minimal HTTP bridge exposing search/status/admin endpoints that call existing Savant engines/CLIs.
- Docker Compose to run: frontend, backend HTTP bridge, Postgres; indexer invoked via Make and optional service command.
- Make targets to bring up/down the stack, show logs, and perform reset+reindex.

## Non‑Goals (v1)
- Authentication, multi‑user, SSR.
- Advanced editor experiences.

## Backend Assumptions and Endpoints
Current Savant services are CLI/MCP stdio. For the SPA, expose a thin HTTP bridge (Ruby Sinatra preferred for cohesion) that:
- Proxies search to `Savant::Context::Engine.search` or the existing FTS helper.
- Surfaces status/admin by invoking existing CLIs and/or DB helpers:
  - `bin/context_repo_indexer status`
  - `bin/context_repo_indexer index all|<repo>`
  - `bin/context_repo_indexer delete all|<repo>`
  - `bin/db_smoke` for health

Proposed endpoints:
- `GET /health` → `{ ok: true }`
- `GET /status` → per‑repo counts and last mtime
- `GET /search?q=<term>&repo=<name?>&lang=<lang?>&page=<n>&perPage=<k>`
- `POST /admin/index` → `{ scope: "all"|"repo", repo? }`
- `POST /admin/reset-and-index` → nukes cache and triggers index all
- `POST /admin/delete` → `{ scope: "all"|"repo", repo? }`

If not adding Ruby HTTP, a Node/Express bridge container can shell out to CLIs; Ruby Sinatra is preferred.

## Frontend UI (MUI)
- Shell
  - AppBar: title, health indicator, quick action for Reset+Index All.
  - Left Drawer: repo and language filters.
  - Content: tabs: Search | Repos.
- Search
  - TextField + search button.
  - Result cards: path, language chip, score, highlighted snippet.
  - Pagination controls.
- Repos
  - DataGrid with columns: name, files, blobs, chunks, last indexed, actions (Index, Delete).
- Feedback
  - Snackbar for success/failure; Backdrop/Progress for running tasks.

## Tech Choices
- React 18 + Vite + TypeScript.
- MUI 6 + Emotion.
- Axios for HTTP.
- React Query for async state/caching.
- Optional: Highlight.js for snippet highlighting.

## Data Contracts
- SearchResult: `{ relPath, chunk, lang, score }`
- StatusItem: `{ repo, files, blobs, chunks, lastIndexedAt }`
- Admin responses: `{ ok: true, message }`

## DevOps
- Docker Compose services:
  - `db`: Postgres (expose 5433 as in repo defaults if desired).
  - `backend`: Ruby app running the HTTP bridge with `DATABASE_URL`; runs `bin/db_migrate` and `bin/db_fts` on start if needed.
  - `frontend`: Vite app served via `vite preview` or nginx.
  - `indexer`: optional service that can run index commands; primary flow via Make.
- Volumes: Postgres data, logs, repo mounts, and `.cache/`.
- Network: single bridge network `savant_net`.

## Make Targets (new/updated)
- `make up`: build and start all services (db, backend, frontend); ensure migrations and FTS are applied.
- `make down`: stop and remove services.
- `make logs`: tail all service logs.
- `make status`: show repo statuses via CLI.
- `make reindex-all`: reset cache and reindex all repos.
  - Steps: remove `.cache/indexer.json` if present; run `bin/context_repo_indexer delete all`; run `bin/context_repo_indexer index all`.
- `make index-repo repo=<name>`: index a single repo.
- `make delete-repo repo=<name>`: delete a single repo.

## Acceptance Criteria
- `make up` launches containers; frontend reachable (e.g., `http://localhost:5173`) with green health indicator.
- Search returns results with correct ranking; repo/lang filters work.
- Repos page lists counts and last indexed time.
- UI button “Reset + Index All” triggers reset and reindex end‑to‑end with visible progress.
- `make reindex-all` performs reset+reindex without UI.
- Compose down/up is idempotent; DB persists unless `make migrate` is invoked.

## Risks & Mitigations
- Bridge complexity: keep Ruby HTTP bridge minimal and reuse existing engines/CLIs.
- Permissions/paths in Docker: mount repo paths read‑only for frontend; ensure `SAVANT_PATH` and `DATABASE_URL` are set.
- Bundle size: code‑split frontend routes and use MUI tree‑shaking.

## Next Steps
1. Scaffold `frontend/` with Vite React TS + MUI and base pages.
2. Use existing Savant Hub HTTP endpoints (mounted Context engine tools) as the backend bridge instead of introducing a new Sinatra app. Map UI actions to:
   - `POST /context/tools/fts/search/call`
   - `POST /context/tools/fs/repo/status/call`
   - `POST /context/tools/fs/repo/index/call`
   - `POST /context/tools/fs/repo/delete/call`
3. Add `docker-compose.yml` service for the React frontend; reuse existing `hub` service for the backend.
4. Update `Makefile` with targets listed.
5. Wire frontend API client and pages; verify end‑to‑end.

## Agent Implementation Plan

Plan: Deliver a minimal, working React SPA that calls the existing Savant Hub HTTP endpoints for search, repo status, and admin actions. Avoid adding a new Ruby HTTP bridge by leveraging Context engine tools exposed via the Hub.

Steps:
1. Frontend scaffold
   - Create `frontend/` with Vite + React + TypeScript + MUI.
   - Pages: Search, Repos; shared API client; basic theming.
   - Local settings persisted in `localStorage.savantHub` for `baseUrl` and `userId` (for required `x-savant-user-id` header).
2. Backend usage (no new server)
   - Use Hub routes: `POST /context/tools/<tool>/call` for `fts/search`, `fs/repo/status`, `fs/repo/index`, and `fs/repo/delete`.
   - Health indicator from `GET /`.
3. Docker Compose
   - Add `frontend` service (Node + Vite preview) alongside existing `postgres` and `hub`.
   - Expose `5173:5173` for quick access.
4. Make targets
   - Add `make up`, `make down`, `make logs` (aggregate), `make reindex-all`, `make index-repo`, `make delete-repo`.
5. Validation
   - Ensure search returns results with query + optional repo filter.
   - Repos page lists counts and last indexed time.
   - “Reset + Index All” triggers delete + index sequentially with progress feedback.

Out of scope:
- New Ruby HTTP endpoints; UI calls Hub directly.
- Auth; multi-user beyond the required header.
