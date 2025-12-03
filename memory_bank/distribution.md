# Distribution & Packaging (MVP)

## Goals
- Public binary distribution via Homebrew
- Reproducible builds (Docker for Linux, local for macOS)
- Offline activation (no server dependency)

## Artifacts
- `dist/savant-<version>-<os>-<arch>.tar.gz`
- `dist/checksums.txt` (SHA256)

## Build Pipeline (Planned)
- `Dockerfile.build` – Linux amd64 builder image
- `scripts/build/build.sh` – assemble self-contained binary
- `scripts/package/package.sh` – tarball packaging
- `scripts/release/checksum.sh` – SHA256 checksums
- `Makefile` – targets: `build`, `package`, `checksum`, `clean-dist`

## Versioning
- Tags `v0.x.y` drive release artifacts
- Embed version from `lib/savant/version.rb`

## Homebrew Formula
- Template: `packaging/homebrew/savant.rb.tmpl`
- Generator reads `dist/checksums.txt` and emits `packaging/homebrew/savant.rb`
- Publish to public tap for MVP; homebrew-core later

## Activation (Runtime)
See `memory_bank/license_activation.md` for the gate enforced at startup.

## Future
- CI-driven releases and formula updates
- Additional targets (arm64 Linux, Windows)

