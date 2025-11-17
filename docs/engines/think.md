# Think Engine (File‑by‑File)

Purpose: Deterministic orchestration and reasoning — plan → execute → next loop.

## Files
- Engine façade: [lib/savant/think/engine.rb](../../lib/savant/think/engine.rb)
- Tools registrar: [lib/savant/think/tools.rb](../../lib/savant/think/tools.rb)
- Workflows: [lib/savant/think/workflows/](../../lib/savant/think/workflows)
- Prompts registry: [lib/savant/think/prompts.yml](../../lib/savant/think/prompts.yml)
- Driver prompts: [lib/savant/think/prompts/](../../lib/savant/think/prompts)
- State files (runtime): `.savant/state/<workflow>.json`

## Tools
- `think.driver_prompt`: versioned bootstrap prompt `{version, hash, prompt_md}`
- `think.plan`: initialize a run and return the first instruction + state
- `think.next`: record step result and return next instruction or final summary
- `think.workflows.list`: list workflow IDs and metadata
- `think.workflows.read`: return raw workflow YAML

## Starter Workflows
- `review_v1`, `code_review_v1`, `develop_ticket_v1`, `ticket_grooming_v1`

## Run
- Stdio: `MCP_SERVICE=think SAVANT_PATH=$(pwd) ruby ./bin/mcp_server`
- HTTP (testing): `MCP_SERVICE=think ruby ./bin/mcp_server --http`

## Code Review Workflow

This workflow is MR‑first and orchestration‑only: Think tells the LLM what to do, but does not run tools itself.

- Start with MR IID (e.g., `!12345`).
- Load project meta from `.cline/config.yml` and parse `project_gitlab`, `project_code`.
- Load rules only from `.cline/rules/` (underscore names preferred):
  - `code_review_rules.md`, `backend_rules.md`, `testing_rules.md`, `style_rules.md`, `savant_rules.md`.
- Fetch MR via GitLab MCP, extract Jira key and fetch the Jira issue.
- Analyze changes, run Context FTS checks, verify with local search, then run RuboCop and RSpec on changed files only (≥ 85% coverage where applicable).
- Map Jira requirements, apply rules, summarize issues and quality, review discussions, compute final verdict, and write a report.

Plan payload example

```bash
ruby ./bin/savant call 'think.plan' \
  --service=think \
  --input='{"workflow":"code_review_v1","params":{"mr_iid":"!12345"}}'
```

Changed-only commands (examples)

Assume you have a list of changed file paths from GitLab MR changes (produced by `analysis.extract_changed_paths`). Here are two ways to run tools only on those files:

1) If you have a newline-separated list in an env var `CHANGED` (or a temp file):

```bash
# RuboCop: only changed Ruby files
FILES=$(printf "%s\n" "$CHANGED" | sed -n 's#^\(.*\.rb\)$#\1#p' | tr '\n' ' ')
if [ -n "$FILES" ]; then
  bundle exec rubocop -f progress $FILES || rubocop -f progress $FILES
else
  echo "No changed Ruby files"
fi

# RSpec: only changed spec files
SPECS=$(printf "%s\n" "$CHANGED" | sed -n 's#^\(spec/.*\)$#\1#p' | tr '\n' ' ')
if [ -n "$SPECS" ]; then
  bundle exec rspec --format progress $SPECS || rspec --format progress $SPECS
else
  echo "No changed spec files"
fi
```

2) If you have a JSON array in `changes.json` (e.g., `[{"new_path":"app/a.rb"},{"new_path":"spec/a_spec.rb"}]`), using `jq`:

```bash
# Extract flat list of paths (prefers new_path, falls back to old_path)
CHANGED=$(jq -r '.[] | .new_path // .old_path' changes.json)

# RuboCop / RSpec same as above
FILES=$(printf "%s\n" "$CHANGED" | sed -n 's#^\(.*\.rb\)$#\1#p' | tr '\n' ' ')
SPECS=$(printf "%s\n" "$CHANGED" | sed -n 's#^\(spec/.*\)$#\1#p' | tr '\n' ' ')
```

Flow (Mermaid)

```mermaid
flowchart TD
  A[think.plan mr_iid] --> B[local.read .cline/config.yml]
  B --> C[analysis.parse_project_meta]
  C --> D[local.read .cline/rules/*]
  D --> E[gitlab.get_merge_request]
  E --> E2[gitlab.get_merge_request_changes]
  E2 --> I[analysis.extract_changed_paths]
  E --> F[analysis.extract_jira]
  F --> G[jira_get_issue]
  E --> H[local.exec: git checkout MR branch]
  I --> J[analysis.graph: code graph + sequence]

  H --> K1[fts/search: lint signals]
  K1 --> K2[local.search: verify lint]
  H --> L1[fts/search: TODO/FIXME/debug]
  L1 --> L2[local.search: verify debug]
  H --> M1[fts/search: security patterns]
  M1 --> M2[local.search: verify security]
  H --> N1[fts/search: Rails anti‑patterns]
  N1 --> N2[local.search: verify Rails]

  I --> O[local.exec: rspec changed specs from MR changes -f doc]
  N2 --> P[local.exec: rubocop only on changed .rb files from MR changes]
  P --> Q[local.exec: rspec only on changed specs from MR changes ≥85%]
  G --> R[analysis.map_requirements]
  Q --> S[analysis.apply_rules + rules/*]
  S --> T[analysis.issues_table]
  T --> U[analysis.quality_summary]
  E --> V[gitlab.get_merge_request_discussions]
  V --> W[analysis.outstanding_items]
  U --> X[analysis.final_matrix thresholds]
  X --> Y[local.write: code-reviews/<ticket>/<ts>.md]
```

Sequence (Mermaid)

```mermaid
sequenceDiagram
  participant LLM
  participant THINK as Think (orchestrator)
  participant LOCAL as Local (workspace/terminal)
  participant GITLAB as GitLab MCP
  participant JIRA as Jira MCP
  participant FTS as Context MCP (fts/search)

  LLM->>THINK: think.plan({ mr_iid: "!12345" })
  THINK-->>LLM: instruction: local.read(.cline/config.yml)
  LLM->>LOCAL: read .cline/config.yml
  LLM->>THINK: think.next(config)
  THINK-->>LLM: instruction: parse_project_meta + load rules (.cline/rules/*)
  LLM->>LOCAL: read rules
  LLM->>THINK: think.next(rules_text)

  THINK-->>LLM: instruction: gitlab.get_merge_request(project_gitlab, mr_iid)
  LLM->>GITLAB: get_merge_request
  GITLAB-->>LLM: MR details
  LLM->>THINK: think.next(mr)

  THINK-->>LLM: instruction: extract Jira key → jira_get_issue
  LLM->>JIRA: jira_get_issue
  JIRA-->>LLM: Jira issue
  LLM->>THINK: think.next(jira)

  THINK-->>LLM: instruction: gitlab.get_merge_request_changes → analysis.extract_changed_paths
  LLM->>GITLAB: get changes
  GITLAB-->>LLM: list of changed files
  LLM->>THINK: think.next(changes)
  THINK-->>LLM: instruction: local.exec checkout + analysis.graph
  LLM->>LOCAL: git checkout build graph from changed paths
  THINK-->>LLM: instruction: analysis.graph
  LLM->>THINK: think.next graph

  THINK-->>LLM: instruction: FTS + local verify lint/debug/security/rails
  LLM->>FTS: fts/search
  FTS-->>LLM: matches
  LLM->>LOCAL: file search verify
  LLM->>THINK: think.next(findings)

  THINK-->>LLM: instruction: local.exec rspec(affected), rubocop, rspec(full ≥85%)
  LLM->>LOCAL: run commands and capture output
  LLM->>THINK: think.next(results)

  THINK-->>LLM: instruction: map_requirements → apply_rules → issues_table → quality_summary
  LLM->>THINK: think.next(assessments)

  THINK-->>LLM: instruction: gitlab.get_merge_request_discussions → outstanding_items
  LLM->>GITLAB: get discussions
  GITLAB-->>LLM: threads
  LLM->>THINK: think.next(outstanding)

  THINK-->>LLM: instruction: final_matrix → local.write(report)
  LLM->>LOCAL: write report file
  LLM->>THINK: think.next(done)
```
