---
name: repo-audit
description: "Scans repositories for hardcoded secrets, API keys, credentials, PII, Web3 private keys, code quality issues, missing documentation, and compliance problems before making them public. Use when preparing to open-source a private repo, auditing a codebase for accidentally committed secrets, or running a pre-release security and compliance checklist."
license: MIT
compatibility: "Requires bash 4.0+, grep, find, file, wc, du, stat. Optional: gitleaks, shellcheck, trivy, jq for enhanced checks."
metadata:
  author: PSDN-AI
  version: "0.1.0"
  category: Security & Compliance
  tags:
    - security
    - secrets
    - compliance
    - code-quality
    - repository-hygiene
---

# Repo Audit Scanner

> Before making a repository public, teams need to ensure it contains no secrets, meets quality standards, has proper documentation, and is free of compliance issues. This Skill provides a comprehensive, automated scan with a clear pass/fail report.

## When Should You Use This?

- You are about to make a private repository public on GitHub, GitLab, or any hosting platform.
- You want to audit a repository for accidentally committed secrets, credentials, or internal references.
- You need a pre-release checklist that covers security, code quality, documentation, hygiene, and legal compliance.

## How This Skill Can Be Used

This Skill supports three consumption models:

| Model | How it works | When to use |
|-------|-------------|-------------|
| **A — Script Execution** | Run `run_scan.sh` and read the Markdown report | You have bash and want automated, deterministic results |
| **B — Knowledge-Driven** | An LLM reads the [Scan Specification](https://github.com/PSDN-AI/nexus-skills/blob/main/skills/repo-audit/references/SCAN_SPEC.md) and performs the checks using its own tools | No bash available, or the LLM is operating in a sandboxed environment |
| **C — Hybrid** | An LLM runs the scripts AND uses the spec to interpret, triage, or extend findings | Best coverage — combines automation with LLM judgment |

## Prerequisites

**Required** (built-in on macOS/Linux):
- `bash` (4.0+), `grep`, `find`, `file`, `wc`, `du`, `stat`

**Optional** (enhanced checks when available):
- `jq` — required to parse JSON output from tools below; without it those checks are SKIPPED
- `gitleaks` — deep secret scanning including git history
- `trufflehog` — additional secret detection patterns
- `shellcheck` — bash script linting
- `trivy` — dependency vulnerability scanning
- `npm` / `pip` — language-specific dependency audits

If an optional tool is not installed, the scanner reports the check as **SKIPPED** rather than failing.

## Quick Start

```bash
# Basic usage — report to stdout
./skills/repo-audit/scripts/run_scan.sh /path/to/target/repo

# Save report to file
./skills/repo-audit/scripts/run_scan.sh /path/to/repo > report.md
```

The scanner executes five check modules in sequence, then generates a Markdown report with an overall verdict.

## Scan Dimensions

The scanner checks five dimensions. For the complete check-by-check specification, see [SCAN_SPEC.md](https://github.com/PSDN-AI/nexus-skills/blob/main/skills/repo-audit/references/SCAN_SPEC.md).

| Dimension | What it covers | Severities |
|-----------|---------------|------------|
| **Security** | Secrets, API keys, private keys, PII, Web3 keys, `.env` files, git history | CRITICAL / HIGH |
| **Code Quality** | TODO comments, shellcheck, dependency vulnerabilities, linter/typechecker config | HIGH / MEDIUM / LOW |
| **Documentation** | README, LICENSE, CONTRIBUTING, .gitignore, SECURITY.md, CHANGELOG | HIGH / MEDIUM / LOW |
| **Repo Hygiene** | Large files, log files, data dumps, build artifacts, OS files, directory depth | HIGH / MEDIUM / LOW |
| **Legal & Compliance** | License validation, internal references, copyright headers | HIGH / LOW |

## Scoring Logic

```
CRITICAL finding exists  →  ❌ NOT READY  (block public release)
HIGH finding exists      →  ⚠️ NEEDS WORK (strongly recommend fixing)
MEDIUM only              →  ✅ READY      (minor improvements suggested)
LOW only                 →  ✅ READY      (cosmetic suggestions)
No findings              →  ✅ READY      (clean)
```

Per-dimension status: any CRITICAL in that dimension → ❌, any HIGH → ⚠️, otherwise ✅.

Every finding includes: severity, file path, line number (where applicable), description, and remediation.

## Report Format

See [REPORT_FORMAT.md](https://github.com/PSDN-AI/nexus-skills/blob/main/skills/repo-audit/references/REPORT_FORMAT.md) for the full report template and severity icons.

## Validation

- The report contains a summary table with all five dimensions and their status.
- Each finding includes file path, line number (where applicable), description, and remediation.
- The overall verdict matches the scoring logic (CRITICAL → NOT READY, HIGH → NEEDS WORK).
- Running the scanner twice on the same repo produces the same results (deterministic).
- For Model B: the LLM should aim to cover all checks listed in the [Scan Specification](https://github.com/PSDN-AI/nexus-skills/blob/main/skills/repo-audit/references/SCAN_SPEC.md). Checks that cannot be performed (e.g., no access to git history) should be reported as SKIPPED with a reason.

## Common Pitfalls

- **Git history not scanned without gitleaks**: The built-in regex checks only scan the working tree (HEAD). Install `gitleaks` to scan the full git history for secrets.
- **False positives on test fixtures**: Files containing example API keys for testing may trigger secret detection. Review findings before acting.
- **Large repos slow the scan**: Repos with deep `node_modules` or build artifacts will be slow. Clean build artifacts before scanning or let the hygiene check flag them.
- **Symlinks**: The scanner follows symlinks. If the repo contains symlinks to outside directories, results may include external files.
- **Model B coverage gap**: An LLM performing checks without scripts cannot run `shellcheck`, `npm audit`, `pip-audit`, `trivy`, or `gitleaks`. These should be reported as SKIPPED with installation instructions.
- **Internal keywords need customization**: The default confidential keywords (`internal-only`, `company-confidential`, etc.) are generic. Set `SCAN_INTERNAL_KEYWORDS` or tell the LLM your company-specific terms for better coverage.
