# PRD: Jira MCP – Advanced Functionality (Additive) — API v3

## Problem
Current Jira PRD focuses on search. Teams need richer, end-to-end Jira operations through MCP—issue lifecycle actions, metadata discovery, and resource-based reads—without breaking the existing `jira_search` tool or default setups. All endpoints and payloads MUST target Jira REST API v3.

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

## MCP Surfaces (Jira REST API v3)
- Resources
  - `jira://issue/<KEY>` → returns JSON issue document (read-only).
- Tools (all additive; names and shapes stable) — Jira REST API v3:
  - `jira_search` (existing): `{ jql: string, limit?: number, start_at?: number }` → `[ { key, summary, status, assignee, updated, url } ]`. Uses `POST /rest/api/3/search` with pagination via `maxResults` and `startAt`.
  - `jira_get_issue`: `{ key: string, fields?: string[] }` → issue JSON. Uses `GET /rest/api/3/issue/{issueIdOrKey}`.
  - `jira_create_issue`: `{ projectKey: string, summary: string, issuetype: string, description?: string, fields?: object }` → `{ key, url }`. Uses `POST /rest/api/3/issue` with v3 field schema.
  - `jira_update_issue`: `{ key: string, fields: object }` → `{ key, updated: boolean }`. Uses `PUT /rest/api/3/issue/{issueIdOrKey}`.
  - `jira_transition_issue`: `{ key: string, transitionName?: string, transitionId?: string }` → `{ key, transitioned: boolean }`. Uses `POST /rest/api/3/issue/{issueIdOrKey}/transitions`.
  - `jira_add_comment`: `{ key: string, body: string }` → `{ id, created }`. Uses `POST /rest/api/3/issue/{issueIdOrKey}/comment`.
  - `jira_delete_comment`: `{ key: string, id: string }` → `{ deleted: boolean }`. Uses `DELETE /rest/api/3/issue/{issueIdOrKey}/comment/{id}`.
  - `jira_assign_issue`: `{ key: string, accountId?: string, name?: string }` → `{ key, assignee }`. Uses `PUT /rest/api/3/issue/{issueIdOrKey}/assignee` with `accountId` (Cloud) preferred.
  - `jira_link_issues`: `{ inwardKey: string, outwardKey: string, linkType: string }` → `{ created: boolean }`. Uses `POST /rest/api/3/issueLink`.
  - `jira_download_attachments`: `{ key: string, destDir?: string }` → `{ count, files: [ { id, filename, path } ] }`. Uses attachment `content` URLs returned by `GET /rest/api/3/issue/{issueIdOrKey}?fields=attachment`.
  - `jira_add_attachment`: `{ key: string, filePath: string }` → `{ id, filename }`. Uses `POST /rest/api/3/issue/{issueIdOrKey}/attachments` with `X-Atlassian-Token: no-check`.
  - `jira_add_watcher_to_issue`: `{ key: string, accountId: string }` → `{ added: boolean }`. Uses `POST /rest/api/3/issue/{issueIdOrKey}/watchers`.
  - `jira_delete_issue`: `{ key: string }` → `{ deleted: boolean }`. Uses `DELETE /rest/api/3/issue/{issueIdOrKey}`.
  - `jira_bulk_create_issues`: `{ issues: Array< { projectKey: string, summary: string, issuetype: string, description?: string, fields?: object } > }` → `{ keys: string[] }`. Uses `POST /rest/api/3/issue/bulk`.
  - Discovery:
    - `jira_list_projects`: `{ query?: string }` → `[ { key, id, name } ]`.
    - `jira_list_fields`: `{ search?: string }` → `[ { id, name, schema, custom?: boolean } ]`.
    - `jira_list_transitions`: `{ key: string }` → `[ { id, name } ]`.
    - `jira_list_statuses`: `{ projectKey?: string }` → `[ { id, name, statusCategory } ]`.

## Request/Response Conventions
- CamelCase field names to align with Jira REST.
- Errors: `{ code, message, details? }` including HTTP status and Jira error body when present.
- Pagination parameters: `limit`, `startAt`; results include `total?`, `nextStartAt?` when applicable.
 - API version: All requests use `/rest/api/3/...` paths; responses normalize to v3 shapes (e.g., `accountId` not `name`).

## Configuration (API v3)
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
- Only REST v3 endpoints are allowed. Server/DC should be mapped to their v2 equivalents internally, but the public contract remains v3-compatible shapes.
- Enforce HTTPS unless explicitly overridden with `JIRA_STRICT_SSL=false`.
- Default bind/usage patterns should avoid exposing credentials in examples.

## Backward Compatibility
- All additions are optional; if Jira env is missing or `JIRA_ALLOW_WRITES=false`, only read/search tools are available.
- `jira_search` inputs/outputs unchanged.
- No changes to unrelated MCP endpoints.

## Implementation Notes (Ruby)
- Lightweight client module handles auth, base paths (v3 Cloud), pagination, and error mapping. For Server/DC, adapt responses to v3-equivalent shapes where minor differences exist.
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
 - All network calls target Jira REST API v3 endpoints.
