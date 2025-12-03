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
- Builds reproducible in Docker environment
