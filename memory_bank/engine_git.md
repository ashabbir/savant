# Git Engine (MCP)

Read‑only, local Git intelligence for agents and review workflows. Surfaces structured diffs, hunks, and file context via a deterministic tool surface.

## Purpose
- Deterministic Git data for agents (no shell parsing in clients)
- Unified tool surface, safe (read‑only)
- Powers MR review, change analysis, and context gathering

## Tools
- `git.repo_status` – repo root, branch, HEAD, tracked file count, language summary
- `git.changed_files` – working tree or staged changes with porcelain status
- `git.diff` – per‑file unified diff parsed into hunks and lines
- `git.hunks` – added/removed line numbers per hunk
- `git.read_file` – read from worktree or `HEAD`
- `git.file_context` – before/line/after slice around a line (worktree or `HEAD`)

## Usage
- Stdio (single engine):
  - `MCP_SERVICE=git SAVANT_PATH=$(pwd) bundle exec ruby ./bin/mcp_server`
- Multiplexer (recommended):
  - `SAVANT_PATH=$(pwd) bundle exec ruby ./bin/mcp_server`
  - Namespaced tools appear as `git.*` alongside other engines (`context.*`, `jira.*`, etc.)

### Examples (JSON‑RPC via stdio)
Repo status:
```
{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"repo_status","arguments":{}}}
```

Changed files (working tree):
```
{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"changed_files","arguments":{}}}
```

Diff for specific path:
```
{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"diff","arguments":{"paths":["lib/savant/framework/mcp/dispatcher.rb"]}}}
```

Hunks for specific path:
```
{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"hunks","arguments":{"paths":["lib/savant/framework/mcp/dispatcher.rb"]}}}
```

Read file from `HEAD`:
```
{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"read_file","arguments":{"path":"README.md","at":"HEAD"}}}
```

Context around a line (worktree):
```
{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"file_context","arguments":{"path":"README.md","line":12,"before":2,"after":2}}}
```

## Notes
- Logs: `logs/git.log` for stdio; multiplexer logs engine lifecycle under `logs/multiplexer.log`.
- Behavior is read‑only. No staging/commit/checkout operations are exposed.
- Large diffs: parsing is line‑based with minimal allocations; still prefer scoping `paths` for very large repos.
