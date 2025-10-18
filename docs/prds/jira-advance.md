# PRD: Jira MCP – Advanced Functionality (Additive)

## Problem
Current Jira PRD focuses on search. Teams need richer, end-to-end Jira operations through MCP—issue lifecycle actions, metadata discovery, and resource-based reads—without breaking the existing `jira_search` tool or default setups.

## Goals
- Add advanced, optional Jira capabilities exposed via MCP tools/resources:
  - Issue lifecycle: get, create, update, transition, comment, assign, link.
  - Metadata: list projects, fields, statuses, transitions.
  - Resources: read issues by key via stable URIs.
- Preserve backward compatibility; `jira_search` remains unchanged.
- Keep configuration simple and secure; Cloud and Server/DC supported.

## Non-Goals
- Webhooks, attachments, and time tracking in v1.
- Admin endpoints or user provisioning.
- LLM-based JQL generation.

## MCP Surfaces
- Resources
  - `jira://issue/<KEY>` → returns JSON issue document (read-only).
- Tools (all additive; names and shapes stable):
  - `jira_search` (existing): `{ jql: string, limit?: number, start_at?: number }` → `[ { key, summary, status, assignee, updated, url } ]`.
  - `jira_get_issue`: `{ key: string, fields?: string[] }` → issue JSON.
  - `jira_create_issue`: `{ projectKey: string, summary: string, issuetype: string, description?: string, fields?: object }` → `{ key, url }`.
  - `jira_update_issue`: `{ key: string, fields: object }` → `{ key, updated: boolean }`.
  - `jira_transition_issue`: `{ key: string, transitionName?: string, transitionId?: string }` → `{ key, transitioned: boolean }`.
  - `jira_add_comment`: `{ key: string, body: string }` → `{ id, created }`.
  - `jira_assign_issue`: `{ key: string, accountId?: string, name?: string }` → `{ key, assignee }`.
  - `jira_link_issues`: `{ inwardKey: string, outwardKey: string, linkType: string }` → `{ created: boolean }`.
  - Discovery:
    - `jira_list_projects`: `{ query?: string }` → `[ { key, id, name } ]`.
    - `jira_list_fields`: `{ search?: string }` → `[ { id, name, schema, custom?: boolean } ]`.
    - `jira_list_transitions`: `{ key: string }` → `[ { id, name } ]`.
    - `jira_list_statuses`: `{ projectKey?: string }` → `[ { id, name, statusCategory } ]`.

## Request/Response Conventions
- CamelCase field names to align with Jira REST.
- Errors: `{ code, message, details? }` including HTTP status and Jira error body when present.
- Pagination parameters: `limit`, `startAt`; results include `total?`, `nextStartAt?` when applicable.

## Configuration
- Env vars (document in `.env.example`):
  - `JIRA_BASE_URL` (e.g., `https://your.atlassian.net`)
  - Cloud auth (preferred): `JIRA_EMAIL`, `JIRA_API_TOKEN`
  - Server/DC auth: `JIRA_USERNAME`, `JIRA_PASSWORD`
  - `JIRA_DEFAULT_FIELDS` (default: `key,summary,status,assignee,updated,priority,issuetype,project`)
  - `JIRA_TIMEOUT_SECONDS` (default: 30)
  - `JIRA_MAX_RESULTS` (default: 50)
  - `JIRA_STRICT_SSL` (default: true)
  - Write guard: `JIRA_ALLOW_WRITES` (default: false) – blocks create/update/transition/comment/assign/link unless true.

## Security
- Prefer token auth; never log secrets; redact auth headers.
- Enforce HTTPS unless explicitly overridden with `JIRA_STRICT_SSL=false`.
- Default bind/usage patterns should avoid exposing credentials in examples.

## Backward Compatibility
- All additions are optional; if Jira env is missing or `JIRA_ALLOW_WRITES=false`, only read/search tools are available.
- `jira_search` inputs/outputs unchanged.
- No changes to unrelated MCP endpoints.

## Implementation Notes (Ruby)
- Lightweight client module handles auth, base paths (v3 Cloud vs v2 Server/DC), pagination, and error mapping.
- Tools call the client; resource reader maps `jira://issue/<KEY>` to GET issue API.
- Validation: require at least one of `transitionName` or `transitionId`; ensure `projectKey`, `issuetype`, `summary` on create.
- Network: timeouts and retries for idempotent GETs; no retries for writes.

## Logging & Telemetry
- Startup: log enabled Jira tools, base host, and write guard status.
- Per call: method, path, Jira status, duration, bytes; warn on 4xx; error on 5xx.

## Acceptance Criteria
- With only `jira_search` configured previously, behavior is unchanged.
- When properly configured, tools perform specified actions and return documented shapes.
- `jira://issue/<KEY>` resource reads return exact issue JSON.
- Write guard blocks mutating tools unless `JIRA_ALLOW_WRITES=true`.
- No secrets in logs; SSL requirements respected by default.

