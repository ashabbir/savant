# Story S-2: Repo Scanning with Ignore Rules

## Summary
Walk configured repos and respect ignore globs.

## Tasks
- Read repo roots from `settings.json`.
- Apply ignores (e.g., `node_modules/**`, `.git/**`, `dist/**`).

## Acceptance
- Ignored paths are skipped; counters reflect processed files.

