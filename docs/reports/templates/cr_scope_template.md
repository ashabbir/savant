---
title: Code Review — Scope & Impact
review_type: cr_scope
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

<one-paragraph verdict and key scores>

# Visuals (Mermaid)

```mermaid
graph TD
  A[Module A] -->|calls| B[Service B]
  A --> C[Config C]
```

```mermaid
flowchart LR
  Deps[Dependencies] --> Added
  Deps --> Updated
  Deps --> Removed
```

```mermaid
%% Size/Churn bars (mock)
graph LR
  File1[File1] ---|120 LOC| LOC1
  File2[File2] ---|80 LOC| LOC2
```

# Evidence

- PR: <link or number>
- Files changed: <count>, LOC: <count>
- Hotspots: <paths and scores>

# Findings

- Scope: <pass/warn/fail + rationale>
- Backward compatibility: <pass/warn/fail + rationale>
- Dependencies: <pass/warn/fail + rationale>
- Config/env: <pass/warn/fail + rationale>
- Cross-repo impact: <pass/warn/fail + rationale>

# Actions

- [ ] <action item> — owner: <name>, due: <date>
