# Workflow: code_review_final

Purpose: Phase 2 of code review — load state from Phase 1, perform impact and cross‑repo analysis, generate diagrams, apply rules, decide safety, and write the final report.

Prerequisite
- Run `code_review_initial` first. Use `ticket={TICKET}` to load the latest state.

Key outputs
- `code-reviews/{TICKET}/{TIMESTAMP}/code_review_final.md` (embedded Mermaid Impact Graph and Sequence Diagram)

Mermaid (high‑level flow)
```mermaid
flowchart TD
  A[Start: think.plan ticket] --> B[Find + load latest state]
  B --> C[Validate state]
  C --> C2[MR discussions]
  C2 --> C3[Outstanding items]

  C --> D[Impact analysis (static)]
  D --> E[Cross‑repo FTS + Memory]
  E --> F[Cross‑repo impact summary]
  F --> G[Requirements gap analysis]
  G --> H[Load rules + apply]
  H --> I[Issues table]

  F --> J[Impact Graph (Mermaid)]
  J --> K[Sequence Diagram (Mermaid)]

  K --> L[Safety decision]
  C3 --> L
  I --> L

  L --> M[Write final report]
  M --> N[Announce completion]
```
