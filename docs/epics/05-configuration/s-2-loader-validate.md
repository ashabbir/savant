# Story S-2: Loader and Validation

## Summary
Load `settings.json`, validate types, and provide clear errors.

## Tasks
- Parse JSON; type-check; surface line/field on error.
- Log effective config at debug level.

## Acceptance
- Invalid config emits actionable error; valid config loads successfully.

