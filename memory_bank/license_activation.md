# Offline License & Activation

## Overview
Savant enforces an offline activation gate for engine and MCP startup. Users activate with `<username>:<key>`, where `key = SHA256(username + SECRET_SALT)`. No network calls are made.

## Implementation
- File: `lib/savant/framework/license.rb`
- Storage: `~/.savant/license.json` (override with `SAVANT_LICENSE_PATH`)
- Salt: `ENV['SAVANT_SECRET_SALT']` (no default in production builds)
- Dev bypass: `SAVANT_DEV=1`

## CLI
```
./bin/savant activate <username>:<key>
./bin/savant status
./bin/savant deactivate
```

## Enforcement
- `lib/savant/framework/boot.rb` – verifies at boot
- `lib/savant/framework/mcp/server.rb` – verifies before starting transport
- Raises on invalid/missing license with a clear remediation message

## Status Semantics
- `valid: true|false`
- `reason: ok | mismatch | missing_file | missing_fields | dev_bypass`

## Operational Notes
- Do not log `SECRET_SALT` or user keys.
- For testing, set `SAVANT_DEV=1` to bypass.
- Support workflow: `savant deactivate` to reset local activation.

