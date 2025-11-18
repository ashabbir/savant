# Workflow: code_review_initial

Purpose: Phase 1 of code review — collect MR data, classify changes, run quality gates and security scans, produce an initial report and state. If gates pass, announce it’s safe to proceed to Phase 2.

Key outputs
- `code-reviews/{TICKET}/{DATE}/code_review_initial.md` (embedded Mermaid Change Graph)
- `.savant/code-review/{TICKET}-{TIMESTAMP}-state.json`

Mermaid (high‑level flow)
```mermaid
flowchart TD
  A[Start: think.plan mr_iid] --> B[Load config (.cline/config.yml)]
  B --> C[GitLab: MR details + changes + diffs]
  C --> C2[Checkout MR branch + safe dev migrate]
  C --> D[Extract changed paths + diff summary]
  D --> E[Classify changes]
  E --> E2[Derive flags (migrations_present, frontend_present) + announce]
  E --> F[Jira: fetch + extract requirements]
  E --> G[Build Change Graph]

  %% DB gate
  E2 --> H{migrations_present?}
  H -- yes --> H1[DB: status + migrate (dev/test)]
  H -- no --> H2[Skip DB operations]

  %% Backend quality
  E --> I[RuboCop (changed Ruby files)]
  I --> J[RSpec (changed specs) + retry on migration]

  %% Frontend gate
  E2 --> K{frontend_present?}
  K -- yes --> K1[ESLint + FE tests]
  K -- no --> K2[Skip FE checks]

  %% Security + diff scans
  E --> L[Security scans: Brakeman, audits]
  D --> M[Diff scans: secrets, debug, migration safety]

  %% Summarize + persist
  I --> N[Quality summary]
  J --> N
  K1 --> N
  L --> N
  M --> N
  N --> O[Evaluate initial gates]
  O --> P[Write code_review_initial.md]
  O --> Q[Write state JSON]
  Q --> R[Announce completion + proceed hint]
```
