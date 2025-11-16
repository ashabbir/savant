# Jira Engine (File‑by‑File)

Purpose: Jira JQL search and CRUD wrappers over Jira REST v3.

## Files
- Engine façade: [lib/savant/jira/engine.rb](../../lib/savant/jira/engine.rb)
- Tools registrar: [lib/savant/jira/tools.rb](../../lib/savant/jira/tools.rb)
- Operations: [lib/savant/jira/ops.rb](../../lib/savant/jira/ops.rb)
- HTTP client: [lib/savant/jira/client.rb](../../lib/savant/jira/client.rb)

## Tools (examples)
- `jira_search`, `jira_get_issue`
- `jira_create_issue`, `jira_update_issue`, `jira_delete_issue`
- `jira_transition_issue`, `jira_link_issues`
- `jira_add_comment`, `jira_delete_comment`, `jira_download_attachments`, `jira_add_attachment`
- `jira_self` (auth check)

## Setup
- Env vars or config file required. Typical env:
  - `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN` (Cloud)
  - or `JIRA_USERNAME`, `JIRA_PASSWORD` (Server/DC)
  - Optional: `JIRA_ALLOW_WRITES=true` to enable mutating tools
- Start: `MCP_SERVICE=jira SAVANT_PATH=$(pwd) ruby ./bin/mcp_server`

