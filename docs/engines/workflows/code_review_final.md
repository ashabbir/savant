# Workflow: code_review_final

Purpose: Phase 2 of code review — load state from Phase 1, perform impact and cross‑repo analysis, generate diagrams, apply rules, decide safety, and write the final report.

Prerequisite
- Run `code_review_initial` first. Use `ticket={TICKET}` to load the latest state.

Key outputs
- `code-reviews/{TICKET}-{TIMESTAMP}.md` (embedded Mermaid Impact Graph and Sequence Diagram)

Mermaid (high‑level flow)
```mermaid
flowchart TD
  A[Start: think.plan ticket] --> B[Find + load latest state]
  B --> C[Validate state]
  C --> D[Impact analysis static]
  D --> E[Cross‑repo FTS + Memory]
  E --> F[Cross‑repo impact summary]
  F --> G[Requirements gap analysis]
  G --> H[Load rules + apply]
  H --> I[Issues table]
  F --> J[Impact Graph Mermaid]
  J --> K[Sequence Diagram Mermaid]
  K --> L[Safety decision]
  L --> M[Write final report]
  M --> N[Announce completion]
```

