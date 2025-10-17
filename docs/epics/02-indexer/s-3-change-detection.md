# Story S-3: Change Detection via mtime+size

## Summary
Skip unchanged files using `(mtime_ns + size)`.

## Tasks
- Cache last-seen metadata per file.
- Compare on subsequent runs to short-circuit.

## Acceptance
- Re-run is fast when no files changed.

