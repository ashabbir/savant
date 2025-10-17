# Jira MCP Requirements

Goals
- Add a Jira tool to the existing Ruby MCP that can query issues via JQL.
- Reuse containerized stack, expose config via env, and provide strong logs.

Non‑Goals
- Full Jira workflow (create/update issues), webhooks, or attachments.

Tooling
- Tool name: `jira_search`
- Input: `{ jql: string, limit?: number, start_at?: number }`
- Output: array of items: `{ key, summary, status, assignee, updated, url }`

Configuration
- `JIRA_BASE_URL` required (e.g., `https://your.atlassian.net`).
- Auth: either `JIRA_EMAIL` + `JIRA_API_TOKEN` (Cloud) or `JIRA_USERNAME` + `JIRA_PASSWORD` (Server).
- Optional `JIRA_FIELDS` comma list; defaults to `key,summary,status,assignee,updated`.

Logging
- Startup logs list available tools.
- Each request logs timing, bytes in/out, and status code.

DX
- `make jira-test jql='project = ABC order by updated desc' limit=5`.
- Compose passes Jira env vars; `.env.example` documents them.

