# Story S-1: Connection and Migrations

## Summary
Establish `pg` connection and idempotent schema creation.

## Tasks
- Provide migration runner; safe to run twice.
- Output schema version/status.

## Acceptance
- Running migrations twice results in no-op; schema present.

