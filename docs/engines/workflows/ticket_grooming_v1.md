# Workflow: ticket_grooming_v1

Purpose: Groom and plan implementation for a ticket — pull the issue, scan the repo for related context, list memory resources, and surface planning guides.

Parameters
- `issueKey`

Mermaid (flow)
```mermaid
flowchart TD
  A[Start: think.plan issueKey] --> B[jira_get_issue]
  B --> C[fts/search issue key or summary]
  B --> D[memory/resources/list]
  D --> E[fts/search guides: README/ADR/CONTRIBUTING/etc.]
```

