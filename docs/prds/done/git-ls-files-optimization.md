# PRD: Git `ls-files` Scan Optimization

## Executive Summary
- Objective: Speed up repository scanning by using `git ls-files` to enumerate files (respecting `.gitignore` and exclude rules) when enabled, falling back to a filesystem walk otherwise.
- Outcome: Significant traversal speedup on large Git repos and accurate ignore handling via Git, without changing chunking, hashing, or persistence logic.

## Background
- Current scanner walks the filesystem (`Find.find`) and applies ignore globs and `.gitignore` patterns manually. This is robust but can be slow in large repos with deep trees.
- Git already knows which files are tracked and which paths are ignored. Leveraging it avoids walking ignored directories and files entirely.

## Goals
- Add an opt-in scan mode that uses `git ls-files` for file enumeration.
- Respect `.gitignore` and standard excludes via Git; still apply explicit config ignores.
- Provide fallback to walking when Git is unavailable or the directory is not a Git repo.

## Non-Goals
- Do not change chunking, hashing, DB schema, or downstream consumers.
- Do not introduce parallel enumeration in this PRD.

## Design
- Config:
  - Global `indexer.scanMode`: `"auto" | "git" | "walk"` (default `"auto"`).
  - Per-repo override: optional `scanMode` on a repo entry.
- Behavior:
  - Mode `git`: attempt `git -C <root> ls-files -z --cached --others --exclude-standard` and use results; on failure, fallback to `walk`.
  - Mode `auto`: if `<root>/.git` exists and `git` works, use Git; else walk.
  - Mode `walk`: always use filesystem traversal with pruning.
- Ignoring:
  - Git mode: Git handles `.gitignore` and exclude rules. Still apply config `ignore` patterns as a second filter.
  - Walk mode: current behavior (merge `.gitignore` and config globs, prune heavy dirs early).
- Error handling: If `git` is not installed or command fails, silently fallback to walk.

## Interfaces
- Settings: No breaking changes. New optional keys accepted without requiring changes to existing configs.
- Code:
  - `Savant::Indexer::Config#scan_mode_for(repo_hash)` returns `:git`, `:walk`, or `:auto`.
  - `Savant::Indexer::RepositoryScanner.new(root, extra_ignores:, scan_mode:)` uses Git-based enumeration when appropriate.

## Risks & Mitigations
- Git not installed: Fallback to walk. Document that installing Git enables the optimization in Docker.
- Untracked files: Using `--others --exclude-standard` includes untracked but not ignored files; aligns with current behavior of indexing non-ignored files.
- Submodules: Not recursed in initial version; can add `--recurse-submodules` later.

## Migration
- Defaults to `auto` (unchanged behavior for non-git repos; git repos will prefer Git if available).
- No CLI or Make changes required.

## Validation
- Compare counts and wall-clock time for walk vs git mode on sample repos.
- Ensure ignore behavior matches expectations with `.gitignore` patterns and explicit config ignores.

