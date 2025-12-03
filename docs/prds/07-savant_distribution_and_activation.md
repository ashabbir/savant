# PRD — Savant Distribution & Activation System
**Owner:** Amd  
**Stage:** MVP (v0.1.x)  
**Purpose:** Ship Savant as a public Homebrew-installable binary with an offline activation key system.  
**Status:** ACTIVE

---

# 1. Purpose
Savant requires a frictionless installation path (`brew install savant`) while preventing unauthorized usage.  
This PRD defines:
- Public binary distribution
- Homebrew formula workflow
- Docker-based reproducible builds
- Offline activation using `<username>:<key>`
- Local license validation at engine startup

No license server.  
No cloud dependency.  
Zero friction for installation.

---

# 2. Problems This Solves
- Developers need a simple install (`brew install savant`)
- Builds must be reproducible across machines
- Need a lightweight gating mechanism for paid access
- Brew must upgrade versions seamlessly
- Product must remain closed-source while binary is public

---

# 3. Objectives

## 3.1 Primary
- Provide a single compiled Savant binary (CLI + Engine + Hub assets)
- Distribute via a **public** Homebrew formula
- Enforce activation using:
  ```
  savant activate <username>:<license_key>
  ```
- Validate license **offline** with SHA256(username + SECRET_SALT)

## 3.2 Secondary
- Create reproducible Docker-based build pipeline
- Automate version tagging + release packaging
- Store activation locally in `~/.savant/license.json`
- Validate license at every engine startup

---

# 4. Non-Goals
❌ No license server  
❌ No online authentication  
❌ No private tap  
❌ No DRM / obfuscation  
❌ No encrypted tokens  

Strictly MVP distribution + offline activation.

---

# 5. Core Features

---

## 5.1 Docker-Based Reproducible Build System
### Requirements
- Docker builder image
- Outputs cross-platform binaries:
  - macOS ARM64
  - macOS AMD64
  - Linux AMD64
- Binary includes:
  - Savant CLI
  - Savant Engine
  - Hub static files

### Acceptance Criteria
- `make build` inside Docker produces consistent binaries

---

## 5.2 Versioning via Git Tags
### Requirements
- Every release must be Git-tagged (`v0.x.y`)
- GitHub Release artifacts map directly to tag
- Brew upgrades tied to version increments

### Acceptance Criteria
- `brew upgrade savant` updates user to latest version

---

## 5.3 Public Homebrew Formula
### Requirements
- Formula references GitHub Release URLs
- Platform-specific URLs + SHA256 checksums
- Install binary to PATH

### Acceptance Criteria
```
brew install savant
brew upgrade savant
```
work with zero friction.

---

## 5.4 Offline Activation System (Username + Key)
### Requirements
- Activation format:
  ```
  <username>:<key>
  ```
- Key = SHA256(username + SECRET_SALT)
- SECRET_SALT hard-coded in binary
- Valid activation stored at:
  ```
  ~/.savant/license.json
  ```

### Activation Flow
1. User installs Savant via Brew  
2. Runs:
   ```
   savant activate amd:KEY123
   ```
3. Engine recomputes expected key  
4. If match → activate  
5. If mismatch → reject  

### Acceptance Criteria
- Engine blocks if not activated
- Works fully offline
- No calls to external APIs

---

## 5.5 Engine Boot License Enforcement
### Requirements
- On engine start:
  1. Load license.json
  2. Validate username + key
  3. Compute expected_key = SHA256(username + SECRET_SALT)
  4. Compare
  5. Allow or block

### Acceptance Criteria
- Wrong/missing key → fatal startup error
- Valid key → continue boot sequence

---

# 6. Technical Constraints
- Engine binary must be compiled (Go/Rust recommended)
- Hub static assets embedded inside binary
- Homebrew formula < 50 lines
- No dynamic runtime dependencies
- Docker required for official builds

---

# 7. Deliverables (MVP)
- `Dockerfile.build` for reproducible builds
- `Makefile` with tasks:
  - `make build`
  - `make package`
  - `make checksum`
- GitHub Release artifacts for each platform
- Homebrew formula with URLs + SHA256
- Activation CLI command
- Boot sequence license validator

---

# 8. Risks
- SECRET_SALT leak → unwanted activations (acceptable for MVP)
- Shared keys → limited control (MVP acceptable)
- Manual Brew formula updates until CI automation exists
- Multi-platform builds may require tuning

---

# 9. Future Improvements (Post-MVP)
- License server with signed tokens
- Expiring keys
- Seat-based licensing
- Private tap for enterprise
- CI automation for Brew formula updates
- Encrypted local activation files
- Feature entitlements in license

---

# 10. Success Criteria
- `brew install savant` works first try
- Activation works offline
- Engine refuses to boot without valid key
- Brew upgrades work without breaking installs

---

# 11. Agent Implementation Plan (MVP)

## 11.1 Overview
Implement offline licensing, reproducible builds, and a Homebrew formula with minimal disruption to the existing Ruby codebase. Ship a single self-contained binary per platform by packaging the Ruby runtime and app code, enforce license at boot, and provide an `activate` CLI. Automate build/package/checksum via Make targets and Docker where feasible.

## 11.2 Scope Decisions (MVP)
- Language: package current Ruby app into a single binary (via Ruby packer) rather than rewriting in Go/Rust.
- Platforms: macOS arm64, macOS amd64, Linux amd64. Build Linux via Docker; build macOS on macOS runners.
- Activation: offline key = SHA256(username + SECRET_SALT); stored at `~/.savant/license.json`.
- Enforcement: gate engine boot and MCP server start. Allow explicit dev bypass via `SAVANT_DEV=1`.
- Distribution: public GitHub Releases + public Homebrew formula. Manual bump for MVP (CI later).

## 11.3 Work Breakdown

1) Licensing & Activation
- Add `lib/savant/framework/license.rb`:
  - `SECRET_SALT` constant (placeholder; replace before release).
  - `License.path` → `~/.savant/license.json`.
  - `License.activate!(username:, key:)` → writes JSON `{username,key,activated_at,host}`.
  - `License.valid?` and `License.verify!` → compute expected_key = SHA256(username + SECRET_SALT).
  - Structured logging on success/failure.
- CLI: extend `bin/savant` with `activate <username>:<key>` subcommand:
  - Parse `user:key`, call `License.activate!`, print result and location.
  - Add `savant status` to show license state (valid/invalid, username, file path).
- Enforcement hooks:
  - `lib/savant/framework/boot.rb`: call `License.verify!` at the beginning of `initialize!` unless `SAVANT_DEV=1`.
  - `lib/savant/framework/mcp/server.rb`: verify on `initialize` or `start` for MCP-only runs.
  - Exit with non‑zero on invalid/missing license with clear message and log.

2) Reproducible Builds
- Add `Dockerfile.build` (builder image) and `scripts/build/build.sh`:
  - Assemble self-contained binary with Ruby + app code for Linux amd64.
  - Stage artifacts to `dist/savant-${os}-${arch}`.
- Add `scripts/package/package.sh` to tarball each binary: `dist/savant-${version}-${os}-${arch}.tar.gz`.
- Add `scripts/release/checksum.sh` to output SHA256 sums into `dist/checksums.txt`.
- Make targets in `Makefile`:
  - `make build` → build all targets (Docker for Linux, local for macOS).
  - `make package` → produce tarballs under `dist/`.
  - `make checksum` → write SHA256 per artifact.
  - `make clean-dist` → remove `dist/`.

3) Versioning & Releases
- Tagging: `make tag VERSION=v0.1.0` → `git tag -a v0.1.0 -m "Savant v0.1.0"`.
- Release: `make release VERSION=v0.1.0` → build, package, checksum, then upload artifacts to GitHub Release (via `gh` if available; otherwise manual).
- Embed version into binary by sourcing `lib/savant/version.rb` at build time and stamping `SAVANT_VERSION` env.

4) Homebrew Formula (Public)
- Template: `packaging/homebrew/savant.rb.tmpl` with placeholders for version, darwin/arm64, darwin/amd64, linux/amd64 URLs and SHA256s.
- Generator: `scripts/release/generate_formula.rb` → reads `dist/checksums.txt` and emits `packaging/homebrew/savant.rb`.
- Manual publish for MVP:
  - Create/maintain a public tap (or submit to homebrew-core later).
  - `brew tap <org/tap>`; `brew install <org/tap>/savant`.
- Make target: `make formula` → generate formula locally ready to copy to tap.

5) Tests & QA
- RSpec: `spec/framework/license_spec.rb`
  - Valid/invalid activation key cases.
  - `activate` CLI writes file and is readable/valid.
  - Boot fails without license; passes with valid license; is bypassed with `SAVANT_DEV=1`.
- Smoke: script to run `savant run --dry-run` and `bin/mcp_server --transport=stdio` with/without license.
- Packaging smoke: unpack each tarball, `./savant --version`, `./savant status`.

6) Documentation
- README updates:
  - Install: `brew install savant` (and Linuxbrew notes).
  - Activate: `savant activate <username>:<key>`; `savant status`.
  - Troubleshooting: where the license file lives; how to reset.
- Update `docs/prds/mvp-checklist.md` with distribution tasks and checkboxes.

7) Security & Operational Notes (MVP)
- Keep `SECRET_SALT` out of VCS history; inject via build step before packaging.
- Log only high‑level activation events; never log secret salt or full key inputs.
- Provide `savant deactivate` to delete local license file for support workflows.

## 11.4 File/Code Changes
- New: `lib/savant/framework/license.rb`
- Update: `bin/savant` (add `activate`, `status`, `deactivate` commands)
- Update: `lib/savant/framework/boot.rb` (early license verification)
- Update: `lib/savant/framework/mcp/server.rb` (license check on start)
- New: `Dockerfile.build`, `scripts/build/build.sh`, `scripts/package/package.sh`, `scripts/release/checksum.sh`
- New: `packaging/homebrew/savant.rb.tmpl`, generated `packaging/homebrew/savant.rb`
- Update: `Makefile` (build/package/checksum/release/formula targets)
- New: `spec/framework/license_spec.rb`

## 11.5 Milestones & Timeline
- M1 (Day 1–2): License module + CLI; boot/MCP enforcement; basic specs green.
- M2 (Day 3–4): Docker build for Linux; local macOS builds; Make targets; checksums.
- M3 (Day 5): Homebrew formula template/generator; README/docs; smoke tests.
- M4 (Day 6): Tag v0.1.0; create GitHub Release; publish tap; internal dogfood.

## 11.6 Acceptance Tests Mapping
- Install via Brew then run `savant status` → shows valid after activation.
- Engine boot without activation → fails with clear error; succeeds after activation.
- MCP `stdio` launch without activation → fails; succeeds after activation.
- `brew upgrade savant` on a new tag → updates and preserves license file.

## 11.7 Rollback/Backout
- Brew: revert formula to previous version.
- App: delete the latest GitHub Release artifacts and retag if needed.
- Local: users can run `savant deactivate` to remove invalid licenses and retry.

---

# 12. Implementation Status (as of this branch)

## 12.1 Shipped in Code
- Offline licensing:
  - New `lib/savant/framework/license.rb` with `activate!`, `status`, `deactivate!`, `expected_key`, `verify!`.
  - Build-time salt embed via `scripts/build/embed_salt.rb` (generates `lib/savant/framework/license_salt.rb`).
  - Dev bypass supported via `SAVANT_DEV=1`.
- Enforcement:
  - `lib/savant/framework/boot.rb` calls `License.verify!` during boot.
  - `lib/savant/framework/mcp/server.rb` verifies before transport start.
- CLI:
  - `savant activate <user>:<key>`
  - `savant status`
  - `savant deactivate`
  - `savant version`
- Distribution pipeline:
  - `Dockerfile.build` for Linux amd64 (ruby-packer).
  - Scripts: `scripts/build/build.sh`, `scripts/package/package.sh`, `scripts/release/checksum.sh`.
  - Homebrew formula generator: `scripts/release/generate_formula.rb` → `packaging/homebrew/savant.rb` (class `Savant`).
  - Tap publish helper: `scripts/release/publish_tap.sh` (copies formula to tap).
  - Make targets: `build`, `package`, `checksum`, `formula`, `tag`, `release`.
- Docs:
  - `docs/getting-started.md` rewritten for Homebrew-first flow.
  - README updated with Homebrew install and activation, and Memory Bank links.
  - Memory Bank added/updated: Indexer, Multiplexer, Hub, Database, Logging, Distribution, License/Activation.
- Tests:
  - `spec/savant/framework/license_spec.rb` basic coverage.
  - `spec/spec_helper.rb` sets `SAVANT_DEV=1` by default to avoid gating other tests.

## 12.2 Release Flow (manual MVP)
1) Build artifacts (embed secret salt):
   - `SAVANT_BUILD_SALT='<secret>' make build`
   - `make package && make checksum`
2) Create Git tag and GitHub Release (requires `gh`):
   - `make tag VERSION=v0.1.0`
   - `make release VERSION=v0.1.0`
3) Generate formula from checksums:
   - `RELEASE_BASE_URL=https://github.com/<org>/savant/releases/download make formula`
   - Result: `packaging/homebrew/savant.rb`
4) Publish to tap:
   - `TAP_DIR=~/code/homebrew-tap scripts/release/publish_tap.sh packaging/homebrew/savant.rb`
5) Install and verify:
   - `brew tap <org/tap>`; `brew install <org/tap>/savant`; `savant version`
6) Activate and run:
   - `savant activate <user>:<key>`; `savant status`; `savant serve --transport=stdio`

## 12.3 Acceptance Criteria Mapping
- Brew install/upgrade: Supported via public tap formula and `make release` flow.
- Offline activation: Implemented (username+key; SHA256(user+salt)).
- Engine boot gating: Implemented in boot and MCP server.
- Reproducible builds: Linux via Docker (ruby-packer). macOS via local `rubyc` if available (optional).

## 12.4 Deviations vs PRD and Notes
- Embedded UI assets: Not yet embedded into the binary. Current approach serves UI from `public/ui` under `SAVANT_PATH` if present. MVP keeps UI optional; embedding can be added post‑MVP.
- Multi-platform matrix: Implemented Linux amd64 in Docker; macOS binaries can be built locally if `rubyc` is installed. CI automation to follow.
- SECRET_SALT: Must be provided at build time via `SAVANT_BUILD_SALT`. Default dev salt exists only for local use.

## 12.5 Next Steps (handoff)
- Add CI (GitHub Actions) for build/package/checksum/release and tap formula update.
- Produce macOS (arm64, x86_64) artifacts consistently; consider using a macOS build runner.
- Optionally embed prebuilt UI assets into release tarballs.
- Harden tests (CLI activation E2E; brew-style smoke on extracted tarballs).
- Document enterprise/private tap option (post-MVP).

- Builds reproducible in Docker environment
