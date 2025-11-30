# PRD --- Savant Git Engine (Diff + Repo Context + Changed Lines)

**Owner:** Amd\
**Priority:** P0\
**Status:** ACTIVE\
**Depends On:** Boot Runtime, Multiplexer, Agent Runtime\
**Target:** Engine MVP (v0.1.0)

------------------------------------------------------------------------

# 1. Purpose

The Git Engine is a **local MCP engine** that provides deterministic,
structured Git intelligence required by the Agent Runtime and MR Review
Agent.

It supplies: - unified diff - changed lines + hunks - file context -
repo metadata - multi-repo impact (via Context Engine)

The Git Engine is read-only, local-first, and powers MR Review.

------------------------------------------------------------------------

# 2. Scope

### In Scope (MVP)

-   Repo detection
-   Diff extraction
-   Changed-line detection
-   Hunk parsing
-   File context APIs
-   Changed files listing
-   MCP tool exposure

### Out of Scope (Post-MVP)

-   write operations (commit, stage)
-   branch switching
-   merge logic
-   remote git interactions
-   full dependency graph

------------------------------------------------------------------------

# 3. Problem Statement

Savant cannot perform MR Review or code-impact analysis without
structured Git data. Raw `git diff` is inconsistent, unstructured, and
not agent-friendly. A proper Git Engine must convert Git state into
machine-readable objects.

------------------------------------------------------------------------

# 4. Goals

### ✔ Provide structured Git data for agents

### ✔ 100% local + deterministic

### ✔ Tool-based MCP surface

### ✔ Safe (read-only)

### ✔ Used by Agent Runtime + MR Agent

### ✔ Integrated into multiplexer

------------------------------------------------------------------------

# 5. Features & Requirements

------------------------------------------------------------------------

## 5.1 Repo Detection

**Requirements:** - git root detection - branch name - HEAD SHA -
tracked files - project language summary

**Tool:** `git.repo_status`

------------------------------------------------------------------------

## 5.2 Diff Extraction

**Requirements:** Extract full unified diff: - added/removed lines -
hunks - per-file metadata

**Tool:** `git.diff`

------------------------------------------------------------------------

## 5.3 Hunk + Changed-Line Extraction

Create structured hunk model:

    file → hunks → added_lines, removed_lines, start/end

**Tool:** `git.hunks`

------------------------------------------------------------------------

## 5.4 File Context API

Provide: - before context - hunk context - after context

**Tools:** - `git.file_context` - `git.read_file`

------------------------------------------------------------------------

## 5.5 Changed Files

Provide: - modified - added - removed files

**Tool:** `git.changed_files`

------------------------------------------------------------------------

## 5.6 Multi-Repo Impact (MVP-Lite)

Using Savant Context Engine search: - symbols - calls - shared libs -
API references

**Tool:** `git.cross_repo_impact` (optional)

------------------------------------------------------------------------

## 5.7 MCP Engine Structure

    lib/savant/git/
      engine.rb
      ops.rb
      tools.rb
      diff_parser.rb
      hunk_parser.rb
      file_context.rb
      repo_detector.rb

------------------------------------------------------------------------

## 5.8 Logging

Write logs to:

    logs/git_engine.log

Track: - diff latency\
- file lookups\
- hunk parsing

------------------------------------------------------------------------

# 6. Deliverables

-   Git Engine (engine.rb / ops.rb / tools.rb)\
-   RepoDetector\
-   DiffParser\
-   HunkParser\
-   FileContext utility\
-   MCP tool registration\
-   README + memory bank updates

------------------------------------------------------------------------

# 7. Success Criteria

-   Multiplexer successfully loads Git Engine\
-   Agent Runtime can request diffs, hunks, context\
-   MR Review Agent runs without errors\
-   100% read-only safe\
-   Stable across repos

------------------------------------------------------------------------

# 8. Risks

-   huge diffs → performance issues\
-   tricky hunk formats\
-   Windows path handling\
-   multi-repo indexing complexity

------------------------------------------------------------------------

# 9. Implementation Strategy

------------------------------------------------------------------------

# Phase 1 --- Core Engine Files (Day 1--2)

### Tasks:

-   Create directory scaffolding\
-   Implement RepoDetector:
    -   find root\
    -   list files\
    -   return metadata
-   Implement DiffParser:
    -   call `git diff --unified=3`\
    -   parse file headers\
    -   parse hunks\
    -   build structured objects

------------------------------------------------------------------------

# Phase 2 --- MCP Tools (Day 3--4)

### Implement:

-   `git.repo_status`
-   `git.diff`
-   `git.hunks`
-   `git.changed_files`
-   `git.file_context`
-   `git.read_file`

### Requirements:

-   consistent return types\
-   clean error handling\
-   multiplexer-compatible JSON

------------------------------------------------------------------------

# Phase 3 --- Integration (Day 5)

### Tasks:

-   Register Git Engine in MCP startup\
-   Verify multiplexer mounts Git Engine\
-   Test tools from CLI using `savant call git.diff`

------------------------------------------------------------------------

# Phase 4 --- Testing (Day 6)

### Test:

-   multi-hunk diffs\
-   added/removed files\
-   large repos\
-   nested repos\
-   multi-repo search (optional MVP)

------------------------------------------------------------------------

# Phase 5 --- Finalization (Day 7)

### Tasks:

-   update README\
-   update memory bank\
-   create example output\
-   add trace logs\
-   clean error paths

------------------------------------------------------------------------

# 10. Architecture Diagram

    Agent Runtime
       ↓ tool calls
    Multiplexer
       ↓ routes
    Git Engine (MCP)
       - repo_status
       - diff
       - hunks
       - changed_files
       - file_context
       - read_file

This powers the MR Review Agent.

------------------------------------------------------------------------

# END OF PRD

------------------------------------------------------------------------

Agent Implementation Plan (by Codex)

1. Create `lib/savant/engines/git/` with:
   - `engine.rb` (façade orchestrator)
   - `ops.rb` (business logic wrapper)
   - `tools.rb` (MCP registrar via DSL)
   - `repo_detector.rb` (root/branch/HEAD/tracked files)
   - `diff_parser.rb` (unified diff → files/hunks/lines)
   - `hunk_parser.rb` (added/removed line numbers per hunk)
   - `file_context.rb` (before/after/hunk context + readers)

2. Expose MCP tools (namespaced by multiplexer as `git.*`):
   - `repo_status` (optional `path`)
   - `changed_files` (optional `staged`, `path`)
   - `diff` (optional `staged`, `paths[]`)
   - `hunks` (optional `staged`, `paths[]`)
   - `file_context` (`path`, optional `line`, `before`, `after`, `at`)
   - `read_file` (`path`, optional `at`=`worktree|HEAD`)

3. Integration:
   - Add `git` to multiplexer default engines so it autostarts.
   - Ensure engine `server_info` and logging use `logs/git.log` via standard transport settings.

4. Tests (RSpec):
   - Create `spec/savant/engines/git/engine_spec.rb` with a temp git repo:
     - Asserts `repo_status` returns root/branch/HEAD
     - Modifies a file; asserts `changed_files`, `diff`, `hunks` are structured and correct
     - Validates `read_file`/`file_context` basics

5. Lint & CI:
   - Run RuboCop auto-correct, ensure style passes
   - Run RSpec suite; iterate to green

6. Docs/UX:
   - Basic README mention: `savant tools` shows `git.*` routes; call via `./bin/savant call git.diff --input='{}'` through multiplexer.
