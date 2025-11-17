# Workflow: code_review_initial

Purpose: Phase 1 of code review — collect MR data, classify changes, run quality gates and security scans, produce an initial report and state. If gates pass, announce it’s safe to proceed to Phase 2.

Key outputs
- `code-reviews/{TICKET}/{TIMESTAMP}/code_review_initial.md` (embedded Mermaid Change Graph)
- `.savant/code-review/{TICKET}-{TIMESTAMP}-state.json`

Mermaid (high‑level flow)
```mermaid
flowchart TD
  A[Start: think.plan mr_iid] --> B[Load config .cline/config.yml]
  B --> C[GitLab: MR + changes + diffs]
  C --> D[Extract changed paths + diff summary]
  D --> E[Classify changes]
  E --> F[Jira: fetch + extract requirements]
  E --> G[Build Change Graph]
  E --> H[DB checks → migrations dev/test]
  E --> I[RuboCop]
  I --> J[RSpec + retry on migration]
  E --> K[Frontend: ESLint + tests]
  E --> L[Security scans: Brakeman, audits]
  D --> M[Diff scans: secrets, debug, migration safety]
  I --> N[Quality summary]
  J --> N
  K --> N
  L --> N
  M --> N
  N --> O[Evaluate initial gates]
  O --> P[Write code_review_initial.md]
  O --> Q[Write state JSON]
  Q --> R[Announce completion + proceed hint]
```
