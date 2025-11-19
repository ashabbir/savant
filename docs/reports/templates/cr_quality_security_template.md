---
title: Code Review — Quality & Security
review_type: cr_quality_security
ticket_id: <id>
repo: <name or path>
pr_number: <number>
branch: <branch>
base_branch: <base>
generated_at: <ISO8601>
reviewer: <name/handle>
tool_version: <version/hash>
data_sources:
  github_mcp: <endpoint>
  savant_context: <endpoint>
---

# Summary

<one-paragraph verdict and key scores>

# Visuals

![Requirements coverage](./assets/cr_quality_security-coverage-matrix.svg)
![Coverage delta](./assets/cr_quality_security-coverage-delta.svg)
![Security issues](./assets/cr_quality_security-security-severity.svg)
![Perf hotspots](./assets/cr_quality_security-perf-hotspots.svg)

# Evidence

- Requirements: <source>
- Tests: <summary>
- Lint/static: <summary>
- Security: <secret/CVE summary>
- Performance: <hotspots>

# Findings

- Requirements coverage: <pass/warn/fail + rationale>
- Tests & coverage: <pass/warn/fail + rationale>
- Lint/static: <pass/warn/fail + rationale>
- Security: <pass/warn/fail + rationale>
- Performance: <pass/warn/fail + rationale>

# Actions

- [ ] <action item> — owner: <name>, due: <date>

