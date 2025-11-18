# Workflow: develop_ticket_v1

Purpose: Develop a ticket from Jira — fetch ticket, branch from base, search context, run tests, and open a PR.

Parameters
- `issueKey`, `base_branch`, `feature_branch`, `title`

Mermaid (flow)
```mermaid
flowchart TD
  A[Start: think.plan issueKey/base/feature/title] --> B[jira_get_issue]
  B --> C[ci.checkout base_branch]
  C --> D[ci.create_branch feature_branch]
  D --> E[fts/search issue key in code]
  E --> F[ci.run_tests feature_branch]
  F --> G[ci.open_pr]
```

