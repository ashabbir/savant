# Repository Guidelines

## Project Structure & Module Organization
- **Docs:** `docs/epics/` for roadmap epics; `docs/prds/prd.md` for product requirements.
- **Planned code:** add runtime code in `src/` and tests in `tests/`. Use `examples/` for runnable snippets and `scripts/` for helper tooling.
- **Naming:** prefer lowercase, hyphenated directory names (e.g., `model-server/`) and snake_case for files unless language norms differ.

## Build, Test, and Development Commands
- This repo currently ships documentation only. When adding code, standardize on a `Makefile` for a consistent DX.
- Example targets to include:
  - `make setup`: install dependencies (language-specific).
  - `make lint`: run formatters/linters.
  - `make test`: run unit tests with coverage.
  - `make dev`: start a local dev server or watcher.

## Coding Style & Naming Conventions
- **Formatting:** enforce an auto-formatter per language (e.g., Python: `black`/`isort`; JS/TS: `prettier` + `eslint`; Rust: `rustfmt` + `clippy`).
- **Indentation:** 2 spaces for web code, 4 spaces for Python; no tabs.
- **APIs:** use explicit, descriptive names; avoid abbreviations; prefer small modules with single responsibility.

## Testing Guidelines
- **Layout:** mirror `src/` under `tests/`.
- **Naming:** Python `test_*.py`; JS/TS `*.spec.ts`/`*.test.ts`.
- **Coverage:** add a minimal threshold (e.g., 80%) once tests exist.
- **Execution:** run via `make test`; add fast, deterministic tests. Include one end-to-end example in `examples/` when applicable.

## Commit & Pull Request Guidelines
- **Commits:** use Conventional Commits (e.g., `feat: add session store`, `fix: handle null IDs`).
- **PRs:** include a clear description, linked issue/epic, screenshots for UX changes, and notes on tests/docs updated. Keep PRs focused and under ~300 lines when possible.

## Security & Configuration
- Never commit secrets. Use `.env.example` and document required variables in PRs.
- Prefer least-privilege configs and avoid production endpoints in examples.

## Agent-Specific Instructions
- Read the tree before edits; prefer small, atomic patches.
- Do not invent files—propose structure and add minimal scaffolding with `Makefile`, `src/`, and `tests/` only when justified in the PR description.
