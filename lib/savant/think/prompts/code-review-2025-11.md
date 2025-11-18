# Driver: Savant Think - Code Review

**Version**: 1.0
**Workflows**: `code_review_initial` + `code_review_final`

---

## Orchestration Loop

Always follow this loop:

1. Call `think.plan` first
2. Execute exactly the tool in `instruction.call` with its `input_template`
3. Pass the tool result to `think.next`
4. Repeat until `done == true`
5. If any required tool is missing or invalid, abort and notify

**Discovery**: To find available workflows, call `think.workflows.list`, then pick one and call `think.plan` with its id and params.

---

## Execution Rules

### Determinism
- Given the same workflow, params, and validated outputs, the sequence is **fixed**
- **Be strict**: Do not invent tools or schema fields. Use only what the registrar advertises
- Follow the DAG dependencies exactly
- Keep rationale concise and actionable

### Payload Discipline

Keep `think.next` payloads compact (< 50KB). Do not paste large file contents, diffs, or entire tickets.

**Prefer**: summaries, counts, and file:line references. If an artifact is large, save it locally and return a path + hash + short preview.

**Good**:
```json
{
  "status": "failed",
  "offenses": { "count": 15, "by_severity": { "error": 2, "warning": 8 } },
  "summary": "15 offenses in 3 files"
}
```

**Bad**:
```json
{
  "raw_output": "...500 lines of RuboCop output...",
  "full_diff": "...10000 lines of git diff..."
}
```

### Analysis Tool Responses

Every `analysis.*` tool MUST return this structure:

```json
{
  "status": "passed|failed|skipped|error",
  "summary": "Human-readable 1-2 sentence summary",
  "details": {
    // Tool-specific metrics (keep minimal)
  },
  "recommendations": [
    // Actionable items only (max 5)
  ]
}
```

### Local Actions

For instructions where `call` looks like `local.exec`, `local.read`, `local.write`, or `local.search`:
- `local.search`: Use your editor/terminal to search files with given `q` and `globs`
- `local.exec`: Run the provided shell `cmd` in the project root and capture output
- `local.read`: Read files and return content
- `local.write`: Write files
- Return snapshots of findings/output to `think.next`

**Local exec usage**:
- OK: Running quality gates (RuboCop, RSpec, ESLint)
- OK: Running security scans (Brakeman, bundler-audit)
- OK: Database migrations
- Avoid: Getting diffs (use `gitlab.get_merge_request_changes` instead)
- Avoid: Listing changed files (use GitLab MCP)

### Cross-Service Calls

For instructions where `call` is a tool exposed by another MCP service:
- `gitlab.*` -> GitLab MCP (e.g., `gitlab.get_merge_request_changes`)
- `fts/search` -> Context MCP full-text search
- `memory/search` -> Context MCP memory search
- `jira_get_issue` -> Jira MCP

Call that service directly and pass the result to `think.next`.

---

## Code Review Standards

### Backend (Ruby/Rails)
- RuboCop: 0 offenses (or documented exceptions)
- RSpec: >=85% coverage, all passing
- Brakeman: No high-confidence warnings
- No SQL injection, proper authorization checks
- Migrations: Reversible, non-destructive, indexed

### Frontend (React/TypeScript)
- ESLint: 0 errors
- TypeScript: No `any` types
- Test coverage: >=90%
- No XSS vulnerabilities

### Security
- No hardcoded secrets (API keys, tokens, credentials)
- No debug statements (binding.pry, console.log, debugger)
- Input validation, parameterized queries
- Proper authentication & authorization

### Database
- Migrations reversible with `down` methods
- No destructive operations without backup plan
- Proper indexes for foreign keys

---

## Analysis Tools

All `analysis.*` tools return structured JSON. Key tools:

- `analysis.classify_mr_changes` - Classify change types (backend, frontend, migrations, database)
- `analysis.parse_rspec` - Parse RSpec output, detect migration errors, trigger auto-retry
- `analysis.parse_rubocop` - Parse RuboCop output
- `analysis.parse_eslint` - Parse ESLint output
- `analysis.parse_security_scans` - Parse Brakeman, bundler-audit, npm audit
- `analysis.detect_secrets_in_diff` - Detect hardcoded secrets in diffs
- `analysis.evaluate_safety` - Final safety verdict (SAFE/CAUTION/RISKY)
- `analysis.extract_diffs` - Extract diff text from GitLab MR changes API
- `analysis.extract_changed_paths` - Extract file list from GitLab API

---

## Commit Analysis

Red flags: Functional regressions, bypassed validation, incomplete testing, multiple fix commits for same feature

Green flags: Better data integrity, corrects test anti-patterns, catches production issues early

---

## Workflows

### code_review_initial (Phase 1)
1. GitLab MCP: Fetch MR data, diffs, files (non-blocking)
2. Classify changes, run quality gates (RuboCop, RSpec, ESLint)
3. Run security scans (Brakeman, audits)
4. Ensure local branch context: checkout MR source branch, then run a safe dev DB migrate (no-op if not Rails).
4. Generate initial report: `code-reviews/{TICKET}/{TIMESTAMP}/code_review_initial.md` (embed Change Graph)
5. Write state: `.savant/code-review/{TICKET}-{TIMESTAMP}-state.json`
6. Decision: If initial gates pass, proceed to `code_review_final` with `ticket={TICKET}`

Pattern scans policy (Phase 1)
- Search only within the changed files from the MR (use local search/terminal).
- Do not use Context FTS for pattern scans in Phase 1.

### code_review_final (Phase 2)
1. Load state from Phase 1
2. Impact analysis, cross-repo search (FTS + memory MCP)
3. Requirements gap analysis, generate Mermaid diagrams (impact graph + sequence)
4. Final safety decision
5. Write final report: `code-reviews/{TICKET}-{TIMESTAMP}.md` (embed both diagrams)

Database policy
- Phase 1 (Initial): Run DB migration status/migrate commands only when MR changes include migration files.
- Phase 2 (Final): No DB operations are executed; analysis only.

---

## Error Handling

- **Missing tools**: Abort and notify (do not invent or substitute)
- **Large payloads**: Summarize before passing to `think.next` (save artifacts to files)
- **RSpec migration failures**: Auto-detect, run migrations, retry RSpec
- **Workflow failures**: Re-run failed phase (state preserved for Phase 2)

---

## Quality Thresholds

**Must Pass**: RuboCop 0 offenses, RSpec >=85% coverage, ESLint 0 errors, No critical/high security vulnerabilities

**Warnings**: Test coverage 70-85%, moderate vulnerabilities, partial requirements

**Blockers**: Test coverage < 70%, critical vulnerabilities, hardcoded secrets, destructive migrations without backup, functional regressions
