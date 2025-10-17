# Story S-2: Tool Contract `search`

## Summary
Implement MCP tool `search` with validated input/output schema.

## Tasks
- Input: `{ q: string, repo?: string, limit?: number }`.
- Output: `{ rel_path, chunk, lang, score }[]`.
- Error handling and schema checks.

## Acceptance
- Bad input yields clear error; valid calls return results.

