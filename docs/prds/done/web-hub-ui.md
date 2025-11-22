# Savant Hub UI — Simple Web Console
**Product Requirements Document (PRD)**
**Version:** 0.1 (Draft)
**Owner:** Amd
**Status:** Draft
**Target Release:** Q1 2026

---

# 1. Purpose

Deliver a minimal, local‑only Web UI for the Savant MCP Hub to:

- Discover mounted engines and tools
- Inspect routes ("rake routes"-style)
- Invoke tools with JSON input (and simple auto‑forms for basic schemas)
- Stream per‑engine logs via SSE and view recent log lines
- Configure base URL and user header, persisted in the browser

No new backend is introduced: the UI talks directly to the existing Hub HTTP/SSE endpoints and serves as static assets.

---

# 2. Goals

1. Dashboard with hub info and mounted engines
2. Engines view with tools list, schema preview, and tool invocation
3. Logs viewer with JSON tail and SSE follow (+ controls)
4. Routes inspector (table of endpoints with expand mode)
5. Settings for Base URL and `x-savant-user-id` (persist to localStorage)
6. Zero backend: static build, optionally served under `/ui` by Hub

---

# 3. Non‑Goals

- Authentication/authorization and multi‑tenant RBAC
- Creation or editing of secrets/tokens (no secret values displayed)
- Complex form generation for deeply nested schemas (JSON editor fallback only)
- Multi‑host clustering, remote auth, or cloud deployments

---

# 4. Users & Use Cases

- Developer: Discover engines/tools, run/test calls, stream logs during local dev
- Operator: Verify hub/engines health, inspect routes, monitor logs quickly

---

# 5. Architecture

- Client‑side SPA (Vanilla JS + lightweight libs) compiled to static assets
- Hosting options:
  - Preferred: Hub serves at `/ui` via Rack::Static
  - Alt: any static server (`vite preview`, `serve`, nginx)
- API: Calls Hub HTTP routes; SSE via EventSource; include `x-savant-user-id`
- Persistence: Browser `localStorage` for `{ baseUrl, userId, theme, tailLines }`

---

# 6. Key Screens

## 6.1 Dashboard
- Hub summary: service/version/transport, PID, uptime
- Engines: name, path, tool count, status, per‑engine uptime
- Click‑through to Engine view

## 6.2 Engine
- Tools list: filterable, shows name + description
- Tool detail:
  - JSON Schema preview
  - Input modes: Simple form (string/int/bool/array of strings) OR raw JSON text
  - Invoke button → POST `/:engine/tools/:name/call` with `{"params": ...}`
  - Result pane with pretty JSON + elapsed time + minimal error state

## 6.3 Logs
- JSON tail: GET `/:engine/logs?n=100` (configurable N)
- SSE follow: GET `/:engine/logs?stream=1` with Start/Stop; line buffer limit
- UI actions: Clear buffer, copy to clipboard

## 6.4 Routes
- Table: method | path | description via GET `/routes` and `?expand=1`
- Filters: method/path substring filter
- “Expand” toggle: include tool call paths (POST `/:engine/tools/<tool>/call`)

## 6.5 Settings
- Base URL (default `http://localhost:9999`)
- User ID for header `x-savant-user-id`
- Theme: light/dark
- Save to localStorage

---

# 7. APIs Consumed (Hub)

- `GET /` → hub overview (dashboard)
- `GET /routes[?expand=1]` → routes table
- `GET /:engine/status` → engine status/uptime
- `GET /:engine/tools` → tool specs
- `POST /:engine/tools/:name/call` → tool invocation
- `GET /:engine/logs?n=100` → last N lines JSON
- `GET /:engine/logs?stream=1[&once=1][&n=]` → SSE streaming logs
- `GET /:engine/stream` → SSE heartbeat (optional keepalive)

All requests must include `x-savant-user-id: <user-id>`.

---

# 8. UI Details

- Header: Hub status pill, base URL, user ID, Settings
- Nav: Dashboard | Engines | Logs | Routes | Settings
- JSON viewer: collapse/expand (lightweight), monospaced font
- Error handling: Render JSON‑RPC errors and HTTP status; no secrets
- Accessibility: Keyboard‑reachable, sufficient contrast, aria labels

---

# 9. Configuration & Defaults

- Base URL default: `http://localhost:9999`
- Tail lines default: `100`; SSE buffer default: `200`
- Persist UI config in `localStorage.savantHub`
- CORS: Prefer serving at `/ui` from Hub to avoid CORS; avoid cross‑origin if possible

---

# 10. Security

- Local dev only; do not expose broadly without auth
- No secret values displayed; sanitize outputs if server redacts
- UI must send `x-savant-user-id`; secrets resolution remains server‑side

---

# 11. Acceptance Criteria

- AC1: Dashboard shows hub + engines within ~1s given reachable Hub
- AC2: Engines view lists tools; tool calls work with JSON input; errors visible
- AC3: Logs view tails JSON and follows SSE with start/stop; UI responsive
- AC4: Routes view lists endpoints; expand shows tool call paths; filter works
- AC5: Settings persist base URL + user header across reloads; all calls include header
- AC6: Build produces static assets; Hub can serve under `/ui`

---

# 12. Milestones

- M1: Scaffold SPA, Settings, Hub client, Dashboard basics
- M2: Engines view (list + call with JSON + simple form), result panel
- M3: Logs view (JSON tail + SSE follow)
- M4: Routes view (base + expand, search/filter)
- M5: Polish (theming, empty/error states), docs
- M6: Integrate static serving under `/ui` from Hub

---

# 13. Tech Choices

- Build: Vite or esbuild
- UI: Vanilla JS + small component helper (Lit or Preact optional)
- Styling: CSS variables; light/dark themes; minimal dependencies
- SSE: Native `EventSource`

---

# 14. Risks & Mitigations

- Schema complexity → provide JSON editor fallback + basic form only
- SSE resource usage → buffer limits, Stop button, backoff on disconnect
- CORS when running UI standalone → recommend serving under `/ui` from Hub

---

# 15. Telemetry

- None; console logs for dev only; must not emit secrets

---

# 16. Out of Scope (Future)

- Secret editing/management UI
- Authentication & API keys
- Team multi‑user dashboards, history, and replay
- External metrics dashboards & Prometheus exporter

