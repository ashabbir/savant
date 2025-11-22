Title
Configurable Repo Scan Strategy (ls default, optional git-ls)

Overview
- Add a repository scan strategy toggle to the indexer so that:
  - Default behavior uses filesystem listing ("ls") for discovering files.
  - Optional behavior uses `git ls-files` ("git-ls") when explicitly requested.
- Mode is configured via `config/settings.json` using `indexer.scanMode`.

Goals
- Provide deterministic, fast default scanning via filesystem listing.
- Allow teams to restrict to tracked files via `git ls-files`.
- Keep existing behavior stable (default to "ls").

Non-Goals
- No automatic fallback between modes within a single run.
- No per-repo override in this iteration (global only).
- No VCS-specific behaviors beyond `git ls-files`.

User Stories
- As an operator, I want to control whether the indexer includes untracked/ignored files (ls) or only tracked files (git-ls), so my index reflects the right scope.
- As a developer, I want the default to remain simple and require no git setup.

Config Changes
- `config/settings.json` under `indexer`:
  - New field: `scanMode` with allowed values: `ls` (default) or `git-ls`.
- Example:
  - `"scanMode": "ls"`
- Schema update:
  - Add enum validation in `config/schema.json` or `Savant::Config` validator.
  - If missing, treat as `ls`.

Behavior
- When `scanMode = ls` (default):
  - Discover files via filesystem walk under repo root.
  - Continue honoring merged ignore patterns (`.gitignore`, `.git/info/exclude`, configured ignore list) as today.
- When `scanMode = git-ls`:
  - Discover files via `git ls-files` executed at repo root.
  - Respect repository ignore rules inherently via git index.
  - Still apply size/binary/hidden/allowlist checks after discovery (unchanged).

CLI/UX
- No new CLI flags necessary; mode controlled via config.
- `bin/context_repo_indexer status` should display the active scan mode in summary lines per repo or global header (optional nice-to-have).
- Logs: Include scan mode at start of each repo scan, e.g., `scan_mode=ls` or `scan_mode=git-ls`.

Validation
- `Savant::Config.load`:
  - Accepts `scanMode` string; validates against `["ls","git-ls"]`.
  - Missing → default to `ls`.
  - Invalid → raise `Savant::ConfigError`.
- Add to `config/settings.example.json` with comment describing the modes.

Implementation Plan
- Update config model:
  - `lib/savant/config.rb`: parse `indexer.scanMode`, default to `ls`, validate enum.
  - `config/settings.example.json`: add `scanMode`.
  - `config/schema.json`: add `scanMode` enum if schema is used for validation.
- Update indexer discovery:
  - `lib/savant/indexer/repository_scanner.rb` (or equivalent):
    - If `scanMode == "git-ls"` and repo is a git repo:
      - Run `git ls-files -z` from repo root; split by NUL; resolve to absolute/relative paths.
      - Handle non-zero exit by logging and falling back to `ls` OR fail hard (choose: log + fallback).
    - Else use existing filesystem walk.
    - Preserve current ignore merging and filters post-discovery.
- Instrumentation/logs:
  - Emit scan mode at start of scan.
- Tests:
  - Unit tests for `Savant::Config` validation/defaulting.
  - Unit/integration tests for scanner selecting the right strategy and applying filters.
  - Smoke: ensure index results differ as expected when untracked files exist.

Edge Cases
- `git-ls` selected but `.git` missing or git not installed:
  - Log a warning and fallback to `ls`.
- Repos with submodules:
  - Treat as today; no special handling in this iteration.
- Performance:
  - `git-ls` should be faster on large repos with heavy ignore rules; ensure streaming parsing for `-z` output to avoid memory spikes.

Risks
- Divergence between ignore handling in `ls` vs `git-ls`.
- Environments without git causing surprises if not clearly logged.
Mitigation: default to `ls`, log explicit warnings, document behavior.

Documentation
- README and comments in `settings.example.json`:
  - “scanMode: ls | git-ls. Default ls scans filesystem; git-ls indexes only tracked files via git.”

