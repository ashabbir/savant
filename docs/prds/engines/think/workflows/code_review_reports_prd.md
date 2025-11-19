# Code Review Reports PRD (Three Independent, Global Workflows)

## Summary
Replace the previous “initial/final” review with three independent, globally configured reports: `cr_scope`, `cr_quality_security`, and `cr_delivery`. Each report runs locally on the checked‑out branch, uses GitHub MCP for diffs/commits (not direct `git diff`), scans the local repo for in‑repo impact, and uses Savant Context only for cross‑repo impact. Reports are stored under `<ticket_id>/<YYYY-MM-DD>/<review_type>.md` and include a mandatory header.

## Goals
- Decouple code review into three standalone, reproducible reports.
- Enforce a single global configuration, rubric, and required parameters.
- Guarantee local branch checkout and local analysis for determinism.
- Use GitHub MCP as the only source for diffs/commits.
- Use Savant Context exclusively for dependent repo impacts.
- Standardize mandatory headers, structure, scores, and verdicts.

## Non‑Goals
- Aggregating the three reports into a meta‑report.
- Per‑repo config divergence; overrides are out of scope.
- Cross‑repo code scanning on local disk (cross‑repo via Savant only).

## Scope
- All repositories reviewed by this process.
- Languages, tests, linters, and migration scripts present in the target repo.
- GitHub MCP and Savant Context as external data sources.

## Global Principles
- Single source of truth: one global config for endpoints, commands, thresholds, and scoring.
- Independence: reports never read or depend on each other.
- Local determinism: always checkout the target branch; run analysis locally.
- Diffs via GitHub MCP: no direct `git diff`; MCP provides diffs/commits/files.
- Impact rules: local impact via disk scan; cross‑repo impact via Savant Context only.
- Business flows: understand requirements → compare implementation → pros/cons → rate.

## Required Run Parameters
- `ticket_id`: Unique work item ID.
- `repo_path`: Local repository path.
- `branch`: Target branch to checkout.
- `base_branch`: Baseline for context.
- `pr_number`: PR number to query via GitHub MCP.
- `date`: ISO `YYYY-MM-DD` for folder naming.
- `reviewer`: Person running the review.

## Global Config (single file)
- `endpoints`: `github_mcp`, `savant_context`
- `commands`: `test_cmd`, `lint_cmd`, `coverage_cmd`, `migrate_cmd` (optional)
- `thresholds`: `coverage_min`, `lint_fail_level`, `perf_warn_ms`, `gate_min_confidence` (default `0.6`)
- `scoring`: 1–5 rubric definitions for Low/Med/High
- `paths`: `reports_root`, `docs_path`, `owners_file`
- `runtime`: `timezone`, `tool_version`, `cache_dir`
- `gates`: Prompt templates for applicability checks per step (see Conditional Step Gates)

## Data Sources
- GitHub MCP: PR metadata, diffs, commits, changed files.
- Local repo: code, configs, tests, migrations, lockfiles.
- CI artifacts (read‑only if present): test/lint/coverage outputs.
- Savant Context: cross‑repo usage/impact lookups.

## Output Location & Naming
- Folder: `<ticket_id>/<YYYY-MM-DD>/`
- Files: `cr_scope.md`, `cr_quality_security.md`, `cr_delivery.md`

## Visuals (Global Requirements)
- Purpose: Communicate structure, scope, risk, and readiness quickly through diagrams/plots.
- Authoring standard: Mermaid‑first (embedded in Markdown). If target viewer lacks Mermaid, export as SVG/PNG and store under `assets/`.
- Storage: `<ticket_id>/<YYYY-MM-DD>/assets/` with filenames prefixed by review type (e.g., `cr_scope-impact-map.svg`).
- Embedding: Use relative paths in Markdown (e.g., `![caption](./assets/cr_scope-impact-map.svg)`).
- Gating: Only generate visuals for applicable sections (respect Conditional Step Gates). If skipped, omit the visual and note “N/A (skipped by gate)”.
- Data sources: Visuals derive only from MCP snapshot, local analysis outputs, and Savant queries (for cross‑repo); never from other reports.
- Minimum set per report (when applicable):
  - cr_scope: Impact map (modules/services/APIs), dependency diff graph, size/churn bar(s).
  - cr_quality_security: Requirements coverage matrix, test coverage delta chart, security issues severity bar, perf risk hotspots.
  - cr_delivery: Migration flow diagram, CI checks status chart, config/flag change tree, rollout plan swimlane.
- Export guidance: Prefer SVG; fall back to PNG for environments lacking SVG support.

## Mandatory Header (identical in all reports)
```yaml
title: <human-readable report title>
review_type: cr_scope | cr_quality_security | cr_delivery
ticket_id: <id>
repo: <name or path>
pr_number: <number>
branch: <checked-out branch>
base_branch: <baseline branch>
generated_at: <ISO8601 timestamp>
reviewer: <name/handle>
tool_version: <version/hash>
data_sources:
  github_mcp: <endpoint/config>
  savant_context: <endpoint/config>
```

---

## Workflow: cr_scope
**Purpose**: Define PR scope, impacted areas, dependencies, and backward‑compatibility risk.

**Inputs**: GitHub MCP diffs/commits, local file tree, CODEOWNERS, lockfiles; Savant Context for dependents.

**Steps**
1. Checkout `branch`; ensure workspace reflects PR head.
2. Pull PR file list, diffs, and commits from GitHub MCP.
3. Local scan: modules/services/APIs/configs touched; dependency adds/updates/removals.
4. Savant Context: query external dependents referencing changed APIs (when applicable).

**Checks**
- Size/churn hotspots.
- Impact map: modules/services/APIs/configs.
- Backward‑compatibility/contract flags.
- Dependency summary.
- Ownership areas (CODEOWNERS).

**Outputs**
- Scope summary, impact map, dependency summary, BC assessment.
- Risk score (1–5) with rationale.
- Visuals (when applicable):
  - Impact map diagram (Mermaid graph or exported SVG/PNG).
  - Dependency changes graph (added/updated/removed).
  - Size/churn bars for top‑N files/modules.

---

## Workflow: cr_quality_security
**Purpose**: Validate requirement coverage, implementation quality, security posture, and performance risk.

**Inputs**: PRD/Jira requirements, GitHub MCP diff, local tests/coverage/lint/static outputs, secret/CVE scans; Savant Context for external flows only.

**Steps (business‑flow first)**
1. Requirements understanding: expected behaviors and acceptance criteria.
2. Implementation review: how current changes implement requirements; pros/cons; rating.
3. Local execution: run tests/coverage and lint/static; inspect perf‑sensitive paths.
4. Security review: secrets in diff, auth/authz on touched endpoints, dependency CVEs.

**Checks**
- Requirements mapping and gaps.
- Tests added/changed and coverage delta; critical path coverage.
- Lint/static issues; autofix viability.
- Performance risk on hot paths/complexity shifts.
- Secrets in diff; auth/authz enforcement; dependency CVEs.

**Outputs**
- Coverage/gap matrix; issue lists with severities; pros/cons.
- Quality score (1–5), security score (1–5), overall risk and rationale.
- Visuals (when applicable):
  - Requirements coverage matrix (table or Mermaid grid; export if needed).
  - Coverage delta bar (before vs after).
  - Security severity bar (High/Med/Low counts), perf hotspots chart.

---

## Workflow: cr_delivery
**Purpose**: Ensure migration safety, CI gates, configs/flags, observability, docs, and merge readiness.

**Inputs**: GitHub MCP diffs for infra/config/docs, local migration scripts, CI status, observability configs.

**Steps**
1. Migrations: run locally (if present); verify reversibility/backfill/rollback plan.
2. CI/gates: collect status; optionally re‑run locally for parity.
3. Config/flags: enumerate changes; verify safe defaults and secret handling.
4. Observability: confirm logs/metrics/traces for new paths; alert changes.
5. Docs: verify user/API/release notes updates.

**Checks**
- Migration/backfill/rollback readiness.
- CI checks status.
- Config/infra diffs; secret handling correctness.
- Observability presence on changed paths.
- Docs completeness.

**Outputs**
- Delivery checklist (Pass/Warn/Fail per item), merge readiness verdict, actions/owners.
- Visuals (when applicable):
  - Migration/backfill/rollback flow (Mermaid flowchart).
  - CI checks status chart (stacked bar or table with icons).
  - Config/flag changes tree; rollout plan swimlane.

---

## Conditional Step Gates (Skippable Steps)

### Gate Standard
- LLM applicability gate per step: “Based on PR title/description, labels, changed files, and diff summary, is STEP applicable? Answer yes/no with confidence 0–1.”
- Execute step only if answer is “yes” and `confidence ≥ gate_min_confidence` (default `0.6`).
- Allowed signals: PR title/labels, commit messages, changed paths, diff hunks, file types; Savant Context only for cross‑repo questions.

### Baseline (Always Run)
- Checkout branch locally (target `branch`).
- Capture MCP snapshot: PR metadata, changed files, diff summary.
- Write report with mandatory header block.
- Lightweight diff secret scan, small diff size/churn stats.

### cr_scope — Skippable Steps
- Public API/BC analysis: skip if no exported symbols/endpoints/schema/contracts changed.
  - Gate: “Any public API or contract changes?”
- Cross‑repo impact (Savant): skip if no public interfaces/contracts changed.
  - Gate: “Will downstream repos be impacted by these interface changes?”
- Dependency analysis: skip if no manifests/lockfiles changed.
  - Gate: “Were runtime/build dependencies added/updated/removed?”
- Config/env review: skip if no config files or env usage changed.
  - Gate: “Are configs/env vars added/modified/removed?”
- Ownership/sign‑offs: skip if no CODEOWNERS file or no owned paths touched.
  - Gate: “Do changed paths map to CODEOWNERS requiring sign‑off?”
- Risk hotspot deep‑dive: skip if churn/size below thresholds and no critical modules touched.
  - Gate: “Do changes hit high‑risk modules or exceed churn thresholds?”
- API versioning notes: skip if no version/compat surface changed.
  - Gate: “Is versioning or deprecation required?”

### cr_quality_security — Skippable Steps
- Business‑flow analysis: skip if PR is internal refactor/test/docs only.
  - Gate: “Does this PR change user‑visible behavior or business rules?”
- Test execution: skip if only non‑runtime files changed and no tests changed.
  - Gate: “Do runtime code or tests change requiring a test run?”
- Coverage delta: skip unless tests ran or coverage artifacts exist.
  - Gate: “Is coverage meaningful to compute for this diff?”
- Lint/static analysis: skip if repo lacks linter/config or no supported languages touched.
  - Gate: “Should lint/static checks run for these file types?”
- Performance assessment: skip if no hot paths/queries/alloc‑heavy code changed.
  - Gate: “Are performance‑sensitive paths likely affected?”
- Secret scan (deep): skip deep scan if only comments/docs changed and entropy cues absent; still run lightweight diff scan.
  - Gate: “Is a deep secret scan warranted beyond a lightweight diff scan?”
- Auth/authz review: skip if no endpoints, policies, or access checks changed.
  - Gate: “Do changes touch authentication/authorization logic?”
- Dependency CVE review: skip if dependencies unchanged.
  - Gate: “Do dependency changes require a CVE check?”
- PII/privacy check: skip if no PII data flows/logging/telemetry touched.
  - Gate: “Do changes affect PII handling, masking, or retention?”

### cr_delivery — Skippable Steps
- Migrations/backfill/rollback: skip if no schema/data migrations or DDL present.
  - Gate: “Are there DB schema/data migrations requiring backfill/rollback?”
- Destructive‑change backup/restore: skip unless destructive or irreversible migrations detected.
  - Gate: “Are any destructive or hard‑to‑reverse DB changes present?”
- CI/gates collection: skip if project has no CI or PR not wired to CI.
  - Gate: “Are CI checks configured and relevant for this PR?”
- Config/env/flags rollout: skip if no env/flag changes.
  - Gate: “Are new/changed feature flags or env vars introduced needing a rollout plan?”
- Observability (logs/metrics/traces): skip if no new/changed code paths lacking instrumentation.
  - Gate: “Do new/changed paths require observability updates?”
- Docs/release notes: skip if no user‑facing behavior/API changes.
  - Gate: “Do changes require docs or release notes?”
- Cross‑repo release coordination (Savant): skip if no shared interfaces/contracts changed.
  - Gate: “Do downstream services require coordinated release?”
- Package/versioning/merge strategy: skip if no publishable package/API surface changed.
  - Gate: “Is a version bump or specific merge strategy needed?”
- External service integration check: skip if no new/changed third‑party service calls.
  - Gate: “Are third‑party integrations added or modified?”
- Cache/invalidation plan: skip if no cache keys/policies changed.
  - Gate: “Do caching semantics or keys change requiring invalidation?”

### Defaults
- Low‑cost checks run always; heavy checks run only if gate passes.
- If gate returns “unknown” or confidence below threshold, default to skip heavy step and record “pending/unknown” with rationale.

---

## Execution Rules
- Branch checkout: always checkout `branch` before any analysis.
- Local analysis: tests/lint/scans run against checked‑out code.
- Diffs/commits: use GitHub MCP exclusively; no direct git diffing.
- Cross‑repo impact: use Savant Context; do not scan other repos on disk.
- Independence: each report re‑derives inputs; never consumes other reports.
- Concurrency: reports may run in parallel; storage is idempotent (overwrite on rerun).

## Report Structure (Markdown)
- Header: mandatory fields block (YAML at top).
- Summary: one‑paragraph verdict and key scores.
- Visuals: embedded Mermaid blocks and/or links to exported SVG/PNG in `assets/`.
- Evidence: MCP links/snippets, local outputs, Savant queries.
- Findings: bulleted checks with Pass/Warn/Fail and rationale.
- Actions: required fixes/follow‑ups with owners and due dates.

## Scoring & Verdicts
- Scores: 1–5 per dimension; map to Low/Med/High using global rubric.
- Verdicts: Pass/Warning/Fail per check; a report‑level verdict with rationale.

## Migration Plan
- Deprecate “initial/final” flows; adopt the three global reports.
- Update contributor docs: parameters, commands, global config, templates.
- Update workflow diagrams: three independent flows, branch checkout, MCP/Savant data paths.
- Update README/CHANGELOG to reflect the new process and storage paths.

## Acceptance Criteria
- Global config is the only configuration source; no per‑repo overrides.
- Each report runs with only the Required Run Parameters.
- Reports write to `<ticket>/<date>/<review_type>.md` and include the mandatory header.
- GitHub MCP is the sole source for diffs/commits/files.
- Local analysis runs on the checked‑out branch.
- Savant Context is used only for cross‑repo impact.
- Clear scores, verdicts, and actionable items are present in every report.
- Applicability gates are enforced for all skippable steps with confidence thresholding.
- Visuals are included for applicable sections per Visuals requirements; otherwise explicitly marked skipped by gate.

## Risks & Mitigations
- MCP availability: implement retries and local caching of MCP responses.
- Tool variability: allow global command templates with repo‑agnostic defaults.
- Flaky CI/tests: mark as Warning with rerun guidance and evidence.
