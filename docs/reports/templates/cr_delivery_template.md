---
title: Code Review — Delivery & Ops Readiness
review_type: cr_delivery
ticket_id: <id>
repo: <name or path>
pr_number: <number>
branch: <branch>
base_branch: <base>
generated_at: <ISO8601>
reviewer: <name/handle>
tool_version: <version/hash>
data_sources:
  github_mcp: <endpoint>
  savant_context: <endpoint>
---

# Summary

<one-paragraph verdict and merge readiness>

# Visuals (Mermaid)

```mermaid
%% Migration Flow (mock)
flowchart TD
  Dev -->|migrate| Stage
  Stage -->|verify| Prod
  Prod -->|rollback?| Stage
```

```mermaid
%% CI Checks Status (mock)
flowchart LR
  Build --> Test --> Lint --> Deploy
```

```mermaid
%% Config/Flags (mock)
flowchart TD
  Config --> Added
  Config --> Changed
  Config --> Removed
```

```mermaid
%% Rollout Plan (mock)
flowchart LR
  Plan --> Canary --> Ramp --> Monitor --> Backout
```

# Evidence

- Migrations: <summary>
- CI: <status>
- Config/flags: <changes>
- Observability: <instruments/alerts>
- Docs: <updates>

# Findings

- Migrations/backfill/rollback: <pass/warn/fail + rationale>
- CI checks: <pass/warn/fail + rationale>
- Config/env/flags: <pass/warn/fail + rationale>
- Observability: <pass/warn/fail + rationale>
- Docs/release notes: <pass/warn/fail + rationale>
- Cross‑repo coordination: <pass/warn/fail + rationale>

# Actions

- [ ] <action item> — owner: <name>, due: <date>
