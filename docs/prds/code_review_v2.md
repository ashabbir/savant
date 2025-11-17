## PRD: Code Review v2

- **Purpose:** Automate a structured code review that: (1) analyzes impact of a change set and checks for breakage risk, (2) generates a visual dependency/impact graph, (3) generates a user interaction sequence diagram indicating where the change lies, (4) makes a clear “safe vs. risky” decision with rationale, and (5) outputs a single end report containing all visuals and evidence. Searches must prefer the local codebase; cross-repo/library impact checks should use Savant Context memory bank and FTS.

### Goals
- Provide a deterministic, reproducible code review workflow from a change set.
- Generate two required visuals: impact graph and sequence diagram.
- Produce an explicit safety decision with evidence and mitigation notes.
- Enforce search policy: local-first; cross-repo via Savant Context memory bank and fs search.
- Emit a single, shareable report embedding all visuals.

### Non-Goals
- Live runtime tracing or production profiling.
- Public internet searches or proprietary vendor integrations.
- Replacing human approvals; this is decision support.

### Inputs
- Change set: `git` target (e.g., `PR #`, commit range `A..B`, or local diff).
- Base branch/ref for comparison (default `origin/main`).
- Project root path.
- Optional: list of related repos for cross-repo checks (must be indexed in Savant).
- Config: thresholds, language hints, include/exclude globs.

### Outputs
- Visual impact graph (Mermaid) highlighting changed areas and affected dependencies.
- Visual sequence diagram (Mermaid) showing user interaction/flow and the change location.
- Safety decision with rationale and a checklist (impacts, tests, migrations, backward compatibility).
- Suggested test plan and follow-ups.
- End report (Markdown) embedding all visuals and linking artifacts.

### Workflow
1. Change Identification
   - Resolve change set (files added/modified/deleted; symbol-level changes when feasible).
   - Summarize diff by file, language, LOC, and high-level intent.

2. Impact Analysis [Gate 1 – user confirmation to proceed]
   - Local-first search: map references, call sites, and dependencies in the current repo using AST/static heuristics and `rg`.
   - Test touchpoints: identify tests affected, fixtures, factories, and mocks.
   - Data/DB impacts: migrations touched, schema references, serialization contracts.
   - Cross-repo/library impacts: use Savant Context memory bank and FTS to find consumers and integration points in indexed repos/gems.
   - Classify risk by category (API change, data shape, side effects, concurrency, security).
   - Produce an “Impacted Areas” table (files, symbols, modules, services).

3. Impact Graph [Gate 2 – generate visual]
   - Build a dependency graph (nodes: modules/files/classes; edges: calls/imports/usage).
   - Highlight changed nodes and impacted nodes; annotate edges with type (call/import/write).
   - Output Mermaid graph and embed in report.

4. Sequence Diagram [Gate 3 – generate visual]
   - Identify likely entry points (e.g., HTTP routes/controllers/CLIs/jobs).
   - Generate one or more sequence diagrams from user entry through affected services/components; highlight the change location(s).
   - Output Mermaid sequence diagram(s) and embed in report.

5. Safety Decision [Gate 4 – decision + rationale]
   - Criteria: backward compatibility, contract changes, migration safety, exception surfaces, performance risk, toggle/rollback, test coverage deltas.
   - Decision: Safe / Needs Caution / Risky, with evidence and required mitigations.
   - Generate suggested tests (unit/integration/e2e) and checks to convert “Risky”→“Safe”.

6. Final Report Assembly
   - Compose Markdown report with: Change Summary, Impact Analysis, Impact Graph, Sequence Diagram(s), Safety Decision, Suggested Tests, Evidence Appendix (queries, code snippets).
   - Save artifacts to `reports/code_review_v2/<date>_<shortsha>/`.

### Driver Prompt (Authoritative)
```
You are Code Review v2. Follow these strict rules:

Scope and Search Policy:
- Project-local analysis MUST use only the local codebase: git diff, file system traversal, AST/static analysis, and ripgrep-style search.
- Cross-repo/library/gem impact checks MUST use Savant Context memory bank and FTS, and local FS index where applicable. Do NOT use public web.
- Prefer deterministic heuristics; annotate confidence levels where inference is used.

Workflow (Gated):
1) Change Identification:
   - Confirm the change set (PR, commit range, or local diff) and summarize touched files and symbols.

2) Impact Analysis (Gate 1 - ask to proceed):
   - Identify impacted modules, call sites, tests, and data/DB surfaces.
   - Local-first search; for external consumers/libraries, query Savant Context memory bank and FTS.
   - Produce an “Impacted Areas” list with evidence (paths, code refs).

3) Impact Graph (Gate 2 - ask to proceed):
   - Generate Mermaid graph: nodes=files/modules/classes; edges=calls/imports/usage.
   - Highlight changed nodes; annotate impacted nodes/edges.
   - Save to impact_graph.mmd and embed in report.

4) Sequence Diagram (Gate 3 - ask to proceed):
   - Identify user entry points (routes/controllers/CLI/jobs).
   - Generate Mermaid sequence diagram(s); highlight where the change occurs.
   - Save to sequence_diagram.mmd and embed in report.

5) Safety Decision (Gate 4 - ask to proceed):
   - Decide Safe / Needs Caution / Risky.
   - Provide rationale referencing evidence and tests; include mitigation steps to achieve Safe.

6) Final Report:
   - Compose a single Markdown report that embeds all visuals (Mermaid code blocks) and includes:
     Change Summary, Impact Analysis, Impact Graph, Sequence Diagram(s), Safety Decision,
     Suggested Tests, and an Evidence Appendix with search queries and references.
   - Save to reports/code_review_v2/<date>_<shortsha>/report.md (plus .mmd files).

Constraints and Tools:
- Do not use the public internet. Use local repo search and AST where possible.
- For cross-repo/library/gem impacts: use Savant Context memory bank and FTS queries and FS search.
- Prefer Mermaid for visuals. Keep diagrams under 150 nodes; chunk if needed.
- Be explicit about assumptions and confidence for each inference.

Outputs:
- report.md with embedded visuals
- impact_graph.mmd
- sequence_diagram.mmd
- auxiliary evidence files if helpful (e.g., impacted_areas.json)
```

### Visuals
- Impact Graph: Mermaid flowchart/graph; highlight changed nodes (e.g., style: red/orange), impacted nodes (yellow), unchanged (grey).
- Sequence Diagram: Mermaid sequence diagram; actors: User/UI/Controller/Service/DB/External; mark change location with note/alt block.

### Acceptance Criteria
- Given a commit range, the tool:
  - Produces an “Impacted Areas” list with concrete code references.
  - Generates a Mermaid impact graph with highlighted changes and dependencies.
  - Generates a Mermaid sequence diagram showing user flow and change position.
  - Emits a safety decision (Safe/Needs Caution/Risky) with explicit criteria and evidence.
  - Saves a single Markdown report embedding both visuals under `reports/code_review_v2/<date>_<shortsha>/`.
  - Adheres to search policy: local-first; cross-repo via Savant Context memory bank and fs search only.

### Technical Approach
- Local analysis: `git` diff parsing; ripgrep searches; basic AST parsing for Ruby (classes/modules/methods) to map symbol references; fallback to file-level dependency heuristics if AST is ambiguous.
- Cross-repo/library: Call Savant Context FTS/memory bank to find references and consumers; include queries and top hits as evidence.
- Visuals: Generate Mermaid (`.mmd`) and embed in Markdown; ensure diagrams are self-contained and readable.

### File Outputs
- `reports/code_review_v2/<date>_<shortsha>/report.md`
- `reports/code_review_v2/<date>_<shortsha>/impact_graph.mmd`
- `reports/code_review_v2/<date>_<shortsha>/sequence_diagram.mmd`
- Optional: `impacted_areas.json`, `search_evidence.md`

### Risks & Mitigations
- Incomplete symbol resolution across languages: fall back to file-level references and annotate confidence.
- Large diffs produce oversized graphs: chunk by module; cap nodes and paginate visuals.
- Savant index stale: instruct to re-index; include last index timestamp in report.

### Milestones
- M1: Local diff analysis + Impacted Areas summary.
- M2: Impact graph generation.
- M3: Sequence diagram generation.
- M4: Safety decision gate with criteria.
- M5: Cross-repo/library impact via Savant Context memory bank + FTS.
- M6: Final report assembly and polish.

### Metrics
- Coverage: % of changed files with mapped dependents.
- Accuracy: Reviewer agreement on impacted areas and decision (sampled).
- Time: End-to-end runtime on medium change sets (<3 minutes target).
- Actionability: % reviews that produce at least one concrete test addition.

### Pre‑Requisites
- Local Git and repo available; change set resolvable.
- Savant DB migrated and FTS enabled; relevant repos indexed if cross-repo checks are desired.
- No network reliance beyond Savant local context sources.
