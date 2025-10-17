# Story S-5: Chunking

## Summary
Chunk files per language with configured sizes and overlaps.

## Tasks
- Use `mdMaxChars`, `codeMaxLines`, and `overlapLines` from settings.
- Infer language by extension; emit chunk metadata.

## Acceptance
- Chunks respect sizes; metadata includes `lang` and positions.

