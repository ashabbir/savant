# Savant Indexer Namespace Refactor PRD

## Executive Summary
- **Objective:** Carve indexing logic into a dedicated `Savant::Indexer` namespace while keeping CLI, Make targets, and downstream flows operational through the new interface.
- **Outcome:** Cleaner modular boundaries, clearer dependency management, and readiness for future standalone or remote indexer deployments without altering search, MCP, or Jira behavior.

## Background
- **Current State:** Indexer classes and CLI entrypoints live alongside other Savant modules, sharing configuration, logging, and database helpers in a single namespace.
- **Pain Points:** Tight coupling obscures ownership, complicates maintenance, and hinders experimentation with new chunking strategies or deployment models.
- **Why Now:** Upcoming work to evolve indexing algorithms and run indexers in isolated environments requires a cleaner, well-defined surface.

## Goals
- **Namespace:** Establish `Savant::Indexer` as the authoritative entrypoint, regrouping all indexing code beneath `lib/savant/indexer/`.
- **Interfaces:** Ensure `bin/index`, `bin/status`, Make targets, and scripts call through the namespace without breaking existing workflows.
- **Config & Dependencies:** Keep `Savant::Config` as source of truth while exposing indexer-specific adapters; inject logger and database handles explicitly.
- **Testing:** Deliver a TDD-driven spec suite that exercises all modules via mocks, avoiding real Postgres or filesystem access.

## Non-Goals
- **Algorithms:** No change to chunking, deduping, or repository traversal logic beyond namespace relocation.
- **Schema:** Postgres schema, migrations, and FTS setup remain untouched.
- **Other Services:** Search, MCP, and Jira components are unaffected aside from namespace references.
- **External APIs:** No new remote indexing protocol or network services introduced in this phase.

## Architecture
- **Namespace Facade:** `lib/savant/indexer.rb` requires submodules, exposes public API, and optionally provides a legacy alias (`Savant::Index`) for transitional compatibility.
- **Core Runtime:** `Runner` orchestrates repository iteration, scanning, chunking, persistence, and cleanup via injected collaborators.
- **CLI Surface:** `CLI` handles command parsing (`index`, `delete`, `status`), delegating to `Runner` and `Admin`.
- **Support Modules:** `RepositoryScanner`, `BlobStore`, chunker hierarchy, `Language` map, `Cache`, `Config` adapter, and `Instrumentation` live in dedicated files under `lib/savant/indexer/`.

## Code Layout
- `lib/savant/indexer.rb`
- `lib/savant/indexer/runner.rb`
- `lib/savant/indexer/cli.rb`
- `lib/savant/indexer/admin.rb`
- `lib/savant/indexer/repository_scanner.rb`
- `lib/savant/indexer/blob_store.rb`
- `lib/savant/indexer/chunker/base.rb`
- `lib/savant/indexer/chunker/code_chunker.rb`
- `lib/savant/indexer/chunker/markdown_chunker.rb`
- `lib/savant/indexer/chunker/plaintext_chunker.rb`
- `lib/savant/indexer/language.rb`
- `lib/savant/indexer/cache.rb`
- `lib/savant/indexer/config.rb`
- `lib/savant/indexer/instrumentation.rb`
- Specs mirrored under `spec/savant/indexer/`

## Command & Make Integration
- **`bin/index`:** Require `savant/indexer`, instantiate `Savant::Indexer::CLI`, and delegate commands.
- **`bin/status`:** Route through `Savant::Indexer::Admin` for repository statistics.
- **Makefile:** Update `index-*`, `delete-*`, `status`, and smoke targets to run `bundle exec ruby -r savant/indexer -e "Savant::Indexer::CLI.run(...)"`.
- **Automation:** Validate Docker-compose services and scripts reference the namespace entrypoint.

## Dependencies
- **Config:** `Savant::Config.load` remains authoritative; `Savant::Indexer::Config` wraps the `indexer` hash and performs additional validation.
- **Database:** `Savant::DB` passed into `Runner`, `Admin`, and `BlobStore`; no direct constants or singletons inside indexer code.
- **Logger:** Default to `Savant::Logger.default`, but accept injected logger for tests or alternate verbosity.
- **Cache Location:** Respect configured cache root; default to repository `.cache/indexer.json` when unspecified.

## Testing & TDD
- **Workflow:** For each module, write failing RSpec (red), implement minimal code (green), then refactor to shared interfaces.
- **Spec Organization:** `spec/savant/indexer/*_spec.rb` mirrors production files; use shared contexts for doubles and factories.
- **Test Doubles:** Employ `instance_double` and spies for database, filesystem, logger, cache, ensuring no real IO.
- **Contract Coverage:** Add integration spec using fakes to mimic runner orchestration without touching Postgres or disk.

## Mocking Strategy
- **Database:** `spec/support/fakes/fake_db.rb` maintains in-memory hashes for repos, blobs, files, and chunks; expectations verify method contracts and parameters.
- **Filesystem:** `RepositoryScanner` depends on an abstract `PathEnumerator`; specs supply enumerables or fakes representing files with attributes (path, size, mtime, binary flag).
- **Cache:** Wrap JSON persistence behind interface; tests inject in-memory hash double to observe reads and writes.
- **Logger & Timing:** Use doubles verifying `info`, `debug`, and `with_timing` invocations; `with_timing` yields immediately.
- **Shared Contexts:** Centralize doubles in `spec/support/shared_contexts/indexer.rb` for reuse across specs.

## Impact Analysis
- **Code:** Moderate refactor of indexer modules, CLI scripts, Makefile, and specs; minimal logic adjustments if namespace migration stays disciplined.
- **Docs:** Update README, architecture notes, onboarding guides, and any references to old namespace or CLI invocation patterns.
- **Tooling:** Ensure CI pipelines and smoke tests reference new namespace; adjust RuboCop or coverage configuration if paths change.
- **Operations:** Validate `docker compose` workflows and environment variables continue to function; ensure logs still appear under `logs/context.log`.

## Risks & Mitigations
- **Missed References:** Risk of lingering old names; mitigate with repository-wide search, temporary alias, and CI checks.
- **Behavior Regression:** Namespace move could break subtle coupling; mitigate via comprehensive spec suite and running `make index-all`, `make smoke`.
- **Fake Drift:** Mocked database/filesystem may diverge from real API; mitigate with contract tests comparing fake versus real interface expectations.
- **Team Adoption:** Developers may continue referencing legacy constants; mitigate with documentation, lint rules, and deprecation warnings.

## Migration Plan
- **Phase 0:** Author fakes, shared contexts, and baseline specs (failing) for each module via TDD.
- **Phase 1:** Introduce namespace skeleton with legacy alias; ensure specs pass with mocks.
- **Phase 2:** Move existing logic into new modules incrementally, updating tests and ensuring red→green cycles.
- **Phase 3:** Update CLI scripts, Make targets, and automation; run smoke tests locally and in CI.
- **Phase 4:** Remove legacy alias once downstream consumers migrate; finalize documentation and changelog entry.

## Rollout
- **Branching:** Use feature branch with logical commits (spec scaffolding, namespace move, CLI integration, docs).
- **CI:** Require `bundle exec rspec spec/savant/indexer` plus existing suites; enforce no real database or disk access in new specs.
- **Communication:** Announce via Slack and CHANGELOG, including migration checklist and command examples.
- **Monitoring:** After deployment, execute `make index-all`, confirm log health, validate search results, and watch for error regressions.

## Open Questions
- **Namespace Depth:** Should we adopt `Savant::Services::Indexer` to align with future service modularization?
- **Public API:** Do we need a documented interface for remote indexer clients now or defer?
- **External Consumers:** Are there downstream scripts or integrations pointing to old class names requiring coordination?
