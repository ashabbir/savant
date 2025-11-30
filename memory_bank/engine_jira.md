# Jira Engine Notes

## Overview
- Activation: `MCP_SERVICE=jira ruby ./bin/mcp_server`
- Files: `lib/savant/engines/jira/{engine.rb,ops.rb,client.rb,tools.rb}`
- Purpose: Jira REST v3 tools (search, read) with guarded writes (create/comment/transition).

## Call Flow
```mermaid
sequenceDiagram
  participant UI as Client
  participant Hub as HTTP Hub
  participant Jira as Jira Registrar
  participant Ops as Jira Ops
  participant API as Jira REST v3

  UI->>Hub: POST /jira/tools/jira_search/call { jql }
  Hub->>Jira: call "jira_search"
  Jira->>Ops: search(jql, limit, start_at)
  Ops->>API: GET /rest/api/3/search?jql=...
  API-->>Ops: issues
  Ops-->>Jira: results
  Jira-->>Hub: results
  Hub-->>UI: results
```

## Config
- Env or secrets: `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN` (or basic auth) and optional `JIRA_ALLOW_WRITES=true`.
- Writes are rejected unless explicitly enabled.

## Notes
- Logs at `/tmp/savant/jira.log` (Hub) or `logs/jira.log` (stdio).
- `make jira-test` and `make jira-self` are useful smoke tests.
