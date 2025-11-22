# PRD: Repo-by-Repo Indexer Progress Logging

## Problem
- Current indexer logs are noisy and unstructured while scanning repositories.
- Operators cannot easily tell which repo is being processed, how many files remain, or whether `git ls-files` vs plain directory walking is in use.
- Lack of per-repo summaries makes it difficult to distinguish indexed vs skipped files during large indexing runs.

## Goals
- Emit a concise, repeatable log block for each repo that clearly shows repo metadata, scan mode, and completion stats.
- Display a terminal progress bar per repo using the `ruby-progressbar` gem so operators can visualize progress across files.
- Summarize indexed vs skipped counts when each repo completes.

## Non-Goals
- Changing skip criteria (size, language, binary) or cache logic.
- Modifying DB persistence or chunking mechanics.
- Introducing historical metrics storage or long-term monitoring.

## Users & Use Cases
- Engineers running `bin/context_repo_indexer index all` who want cleaner feedback for each repo in long sessions.
- Operators debugging why a repo took a long time or skipped many files due to unchanged cache entries.

## Scope
- One log stanza per repo with the format:
  - Header delimiter (e.g., `======`).
  - `name: <repo>`
  - `total_files: <count>`
  - `scan_mode: git-ls|ls`
  - Inline progress bar updated per processed file.
  - Footer lines `indexed: <n>` and `skipped: <n>` before trailing delimiter.
- Use `ruby-progressbar` (already in the bundle) for rendering; hide bar when `verbose` is false.

## Backward Compatibility
- Existing CLI flags and behaviors remain unchanged.
- Verbose per-file logging stays available when enabled; progress bar supplants repetitive `progress:` lines by default.
- Non-interactive environments (e.g., CI logs) should still show textual progress updates from the bar.

## Telemetry & Logging
- Start log: `name`, `total_files`, `scan_mode`.
- Progress bar label `indexing` with dynamic counts.
- Completion log: `indexed`, `skipped`, elapsed duration (if available).

## Acceptance Criteria
- Running the indexer over multiple repos prints a clearly separated block per repo with the exact fields listed above.
- Progress bar advances as files are processed and completes at repo end.
- Indexed/skipped counts match the existing summary totals.
- Behavior is covered by unit or integration tests for the new instrumentation helper (if practical) or by verifying logger output in specs.

## Implementation Sketch
- Extend `Savant::Indexer::Runner` to instantiate a `ProgressBar` for each repo.
- Track per-repo counters (indexed, skipped) separate from global totals.
- Replace verbose `progress:` log lines with bar increments; keep debug logs for skip reasons when `verbose`.
- Add helper to `Savant::Indexer::Instrumentation` to format the new log block and ensure delimiters.

## Agent Implementation Plan
1. Update `lib/savant/indexer/instrumentation.rb` with helpers to emit repo headers/footers and to create a `ProgressBar` instance with safe fallbacks.
2. Enhance `lib/savant/indexer/runner.rb` to use the new instrumentation helpers, track per-repo indexed/skipped counts, and drive the progress bar instead of raw `progress:` logs.
3. Expand `spec/savant/indexer/runner_spec.rb` (or new specs) to assert repo-level logging fields and ensure the `git-ls` scan mode log remains informative.
4. Run `bundle exec rubocop -A` and `bundle exec rspec` to verify lint and tests before finalizing the branch.
