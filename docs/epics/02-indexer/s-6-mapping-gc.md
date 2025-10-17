# Story S-6: Mapping and Garbage Collection

## Summary
Track current path → blob mapping and remove stale entries.

## Tasks
- Update `file_blob_map` after scans.
- Remove mappings for deleted or moved files.

## Acceptance
- DB reflects current filesystem state after re-indexing.

