---
title: Code Review — Quality & Security
review_type: cr_quality_security
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
%% Requirements Coverage Matrix (mock)
flowchart TD
  R1[Req 1] --> T1[Test A]
  R2[Req 2] --> T2[Test B]
```

```mermaid
%% Coverage Delta (mock)
graph LR
  Before ---|75%| B[Coverage]
  After  ---|78%| A[Coverage]
```

```mermaid
%% Security Severity (mock)
graph LR
  High:::h ---|3| H[High]
  Med:::m  ---|5| M[Medium]
  Low:::l  ---|8| L[Low]
  classDef h fill:#f66,stroke:#f00;
  classDef m fill:#fc6,stroke:#f90;
  classDef l fill:#6f6,stroke:#0a0;
```

```mermaid
%% Perf Hotspots (mock)
flowchart TD
  Hot1[Path A] --> Reason1
  Hot2[Path B] --> Reason2
```

# Evidence

- Requirements: <source>
- Tests: <summary>
- Lint/static: <summary>
- Security: <secret/CVE summary>
- Performance: <hotspots>

# Findings

- Requirements coverage: <pass/warn/fail + rationale>
- Tests & coverage: <pass/warn/fail + rationale>
- Lint/static: <pass/warn/fail + rationale>
- Security: <pass/warn/fail + rationale>
- Performance: <pass/warn/fail + rationale>

# Actions

- [ ] <action item> — owner: <name>, due: <date>
