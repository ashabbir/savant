# Story S-4: Hash + Blob Deduplication

## Summary
Store identical content once using xxh3/SHA256 keyed blobs.

## Tasks
- Compute content hash; insert new blobs if unseen.
- Reuse existing blob_id when hash matches.

## Acceptance
- Duplicate files map to a single blob; mappings update correctly.

