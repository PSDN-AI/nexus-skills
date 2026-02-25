---
name: repo-public-readiness
description: "Scans repositories for hardcoded secrets, API keys, credentials, PII, Web3 private keys, code quality issues, missing documentation, and compliance problems before making them public. Use when preparing to open-source a private repo, auditing a codebase for accidentally committed secrets, or running a pre-release security and compliance checklist."
license: MIT
compatibility: "Requires bash 4.0+, grep, find, file, wc, du, stat. Optional: gitleaks, shellcheck, trivy, jq for enhanced checks."
metadata:
  author: PSDN-AI
  version: "1.0.0"
---

# Repo Public Readiness Scanner

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
| **B — Knowledge-Driven** | An LLM reads this document and performs the checks using its own tools | No bash available, or the LLM is operating in a sandboxed environment |
| **C — Hybrid** | An LLM runs the scripts AND uses this document to interpret, triage, or extend findings | Best coverage — combines automation with LLM judgment |

**Model A** — see [Quick Start](#quick-start). **Model B** — see [Scan Specification](#scan-specification). **Model C** — use both.

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
./skills/repo-public-readiness/scripts/run_scan.sh /path/to/target/repo

# Save report to file
./skills/repo-public-readiness/scripts/run_scan.sh /path/to/repo > report.md
```

The scanner executes five check modules in sequence (Security → Code Quality → Documentation → Repo Hygiene → Legal/Compliance), then generates a Markdown report with an overall verdict.

---

## Scan Specification

This section is the complete reference for **what to check, how to check it, and how to classify findings**. An LLM reading only this section should be able to perform a full repo public readiness audit.

### Scoring Logic

```
CRITICAL finding exists  →  ❌ NOT READY  (block public release)
HIGH finding exists      →  ⚠️ NEEDS WORK (strongly recommend fixing)
MEDIUM only              →  ✅ READY      (minor improvements suggested)
LOW only                 →  ✅ READY      (cosmetic suggestions)
No findings              →  ✅ READY      (clean)
```

Per-dimension status: any CRITICAL in that dimension → ❌, any HIGH → ⚠️, otherwise ✅.

### Finding Format

Every finding must include:
- **Severity**: CRITICAL / HIGH / MEDIUM / LOW
- **File path** (relative to repo root)
- **Line number** (where applicable, `-` if not)
- **Description**: What was found
- **Remediation**: How to fix it

---

### Dimension 1: Security

The highest-priority dimension. Any CRITICAL here blocks public release.

#### 1.1 `.env` Files

| Aspect | Detail |
|--------|--------|
| **Severity** | CRITICAL |
| **What to find** | Any file named `.env` or `.env.*` |
| **Exclude** | `.env.example`, `.env.sample`, `.env.template` |
| **Remediation** | Remove file, add `.env` to `.gitignore` |

#### 1.2 Private Key Files

| Aspect | Detail |
|--------|--------|
| **Severity** | CRITICAL |
| **What to find** | Files with extensions: `.pem`, `.key`, `.p12`, `.pfx` |
| **Also find** | Files named: `id_rsa`, `id_ed25519`, `id_ecdsa`, `id_dsa` |
| **Remediation** | Remove file, rotate the key immediately |

#### 1.3 Private Key Content

| Aspect | Detail |
|--------|--------|
| **Severity** | CRITICAL |
| **Pattern** | `BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY` |
| **Scan scope** | All text files < 1MB |
| **Remediation** | Remove the key content, rotate credentials |

#### 1.4 AWS Credentials

| Aspect | Detail |
|--------|--------|
| **Severity** | CRITICAL |
| **Patterns** | `AKIA[0-9A-Z]{16}` (access key ID), `aws_secret_access_key\s*=` |
| **Scan scope** | Source files (see [File Types Scanned](#file-types-scanned)) |
| **Remediation** | Remove and rotate AWS credentials |

#### 1.5 Generic Hardcoded Secrets

| Aspect | Detail |
|--------|--------|
| **Severity** | HIGH |
| **Pattern** | `(api[_-]?key|api[_-]?secret|auth[_-]?token|access[_-]?token|secret[_-]?key|private[_-]?key|password)\s*[:=]\s*["'][A-Za-z0-9+/=_-]{8,}` |
| **Case** | Case-insensitive |
| **Remediation** | Move secret to environment variable or vault |

#### 1.6 Hardcoded IP Addresses

| Aspect | Detail |
|--------|--------|
| **Severity** | HIGH |
| **Pattern** | `\b([0-9]{1,3}\.){3}[0-9]{1,3}\b` |
| **Whitelist** | `127.0.0.1`, `0.0.0.0`, `255.255.255.*`, `169.254.169.254` |
| **Also exclude** | Version strings (e.g., `1.2.3.4-beta`), wildcard patterns (`.*`) |
| **Remediation** | Replace with configurable hostname or DNS |

#### 1.7 PII — Email Addresses

| Aspect | Detail |
|--------|--------|
| **Severity** | HIGH |
| **Pattern** | `[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}` |
| **Whitelist** | `*@example.com`, `*@example.org`, `*@localhost`, `*@users.noreply.github.com`, `noreply@*`, `*@spdx.org` |
| **Remediation** | Remove personal email or replace with generic contact |

#### 1.8 PII — Phone Numbers

| Aspect | Detail |
|--------|--------|
| **Severity** | HIGH |
| **Pattern** | `(\+?1[-.\s]?)?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}` |
| **Exclude** | Lines containing: `test`, `mock`, `fake`, `example`, `fixture`, `sample`, `placeholder`, `0000`, `1234`, `5551` |
| **Remediation** | Remove personal phone numbers before going public |

#### 1.9 GitHub Actions — Hardcoded Secrets

| Aspect | Detail |
|--------|--------|
| **Severity** | CRITICAL |
| **Scope** | `.github/workflows/*.yml` and `*.yaml` |
| **Pattern** | `(api[_-]?key|token|password|secret|credential)\s*[:=]\s*["'][A-Za-z0-9+/=_-]{8,}` |
| **Remediation** | Use `secrets.YOUR_SECRET` instead of hardcoded values |

#### 1.10 GitHub Actions — Script Injection

| Aspect | Detail |
|--------|--------|
| **Severity** | HIGH |
| **Scope** | `.github/workflows/*.yml` and `*.yaml` |
| **Pattern** | `\$\{\{\s*github\.event\.(issue|pull_request|comment)\.(title|body|head\.ref)` |
| **Why** | Attacker-controlled input interpolated into `run:` steps |
| **Remediation** | Use an intermediate environment variable instead of inline expression |

#### 1.11 Git History Scanning (gitleaks)

| Aspect | Detail |
|--------|--------|
| **Severity** | CRITICAL per finding |
| **Tool** | `gitleaks detect --source <repo> --report-format json` |
| **Requires** | `gitleaks` + `jq` |
| **Fallback** | SKIPPED if either tool is missing — note that built-in regex checks only scan HEAD, not history |

#### 1.12 Web3 — Hex Private Keys

| Aspect | Detail |
|--------|--------|
| **Severity** | CRITICAL |
| **Pattern** | `(private[_-]?key|secret[_-]?key|signer|wallet|account)\s*[:=]\s*["']?0x[0-9a-fA-F]{64}` |
| **Why** | Bare 256-bit hex strings used as wallet private keys across EVM chains (Ethereum, Polygon, BSC, Arbitrum, etc.) |
| **Exclude** | Known zero/test key: `0x0000...0000` (64 zeroes) |
| **Remediation** | Remove key and transfer funds to a new wallet immediately |

#### 1.13 Web3 — BIP-39 Mnemonic / Seed Phrases

| Aspect | Detail |
|--------|--------|
| **Severity** | CRITICAL |
| **Detection strategy** | Find sequences of exactly 12, 15, 18, 21, or 24 space-separated words (valid BIP-39 lengths) where ≥ 80% match the BIP-39 English wordlist (2048 words) |
| **Context clues** | Lines containing `mnemonic`, `seed`, `recovery`, `phrase`, `12 words`, `24 words` near a word sequence |
| **Wordlist** | Embedded at `scripts/data/bip39_english.txt` (sourced from [BIP-39 spec](https://github.com/bitcoin/bips/blob/master/bip-0039/english.txt)) |
| **Exclude** | Known test mnemonics (e.g., Hardhat's default `test test test...junk`) |
| **Performance** | Two-pass: scan lines with context clues first, then validate bare sequences in config/env files |
| **Remediation** | Remove mnemonic and transfer funds to a new wallet with a fresh seed |

#### 1.14 Web3 — Solana Private Keys

| Aspect | Detail |
|--------|--------|
| **Severity** | CRITICAL |
| **Pattern (base58)** | Base58 string of 87-88 characters (`[1-9A-HJ-NP-Za-km-z]{87,88}`) near keywords: `solana`, `keypair`, `phantom`, `secret` |
| **Pattern (JSON)** | JSON files containing an array of exactly 64 integers (Solana keypair byte-array format) |
| **Exclude** | Public keys (32-byte / 43-44 chars base58) — only flag 64-byte keypairs |
| **Remediation** | Remove keypair and generate a new wallet |

#### 1.15 Web3 — Keystore / Wallet Files

| Aspect | Detail |
|--------|--------|
| **Severity** | HIGH |
| **File patterns** | `*.keystore`, `*.wallet`, `UTC--*` (Ethereum keystore naming convention) |
| **Content pattern** | JSON containing `"crypto"` + `"ciphertext"` + `"kdf"` (Ethereum keystore v3 format) |
| **Remediation** | Remove wallet file — consider rotating if password was weak |

#### 1.16 Web3 — Hardhat / Foundry Config with Keys

| Aspect | Detail |
|--------|--------|
| **Severity** | CRITICAL |
| **Files** | `hardhat.config.js`, `hardhat.config.ts`, `foundry.toml` |
| **Pattern** | `0x[0-9a-fA-F]{64}` anywhere in the config file, or `accounts:\s*\["0x[0-9a-fA-F]{64}"` |
| **Remediation** | Use environment variables or a secrets manager — never commit keys in config |

---

### Dimension 2: Code Quality

#### 2.1 TODO / FIXME / HACK Comments

| Aspect | Detail |
|--------|--------|
| **Severity** | LOW |
| **Pattern** | `\b(TODO|FIXME|HACK|XXX)\b` (case-insensitive) |
| **Scan scope** | Source files (see [File Types Scanned](#file-types-scanned)) |
| **Self-exclude** | Skip matches inside the scanner's own scripts |
| **Remediation** | Resolve or remove before public release |

#### 2.2 Shell Script Linting (shellcheck)

| Aspect | Detail |
|--------|--------|
| **Tool** | `shellcheck -f json` |
| **Requires** | `shellcheck` + `jq` |
| **Severity mapping** | error → HIGH, warning → MEDIUM, info/style → LOW |
| **Scope** | All `*.sh` files in the repo |
| **Fallback** | SKIPPED if tools missing |

#### 2.3 npm Dependency Vulnerabilities

| Aspect | Detail |
|--------|--------|
| **Trigger** | `package.json` exists in repo root |
| **Tool** | `npm audit --json` |
| **Requires** | `npm` + `jq` |
| **Severity** | HIGH for any critical or high vulnerabilities |
| **Remediation** | `npm audit fix` or update dependencies |

#### 2.4 Python Dependency Vulnerabilities

| Aspect | Detail |
|--------|--------|
| **Trigger** | `requirements.txt` exists in repo root |
| **Tool** | `pip-audit -r requirements.txt --format json` |
| **Requires** | `pip-audit` + `jq` |
| **Severity** | HIGH for any vulnerabilities |
| **Remediation** | Update affected packages |

#### 2.5 Filesystem Vulnerability Scan (trivy)

| Aspect | Detail |
|--------|--------|
| **Tool** | `trivy fs --format json --severity HIGH,CRITICAL <repo>` |
| **Requires** | `trivy` + `jq` |
| **Severity** | HIGH for any high/critical findings |
| **Fallback** | SKIPPED if tools missing |

#### 2.6 Python Linter Configuration

| Aspect | Detail |
|--------|--------|
| **Trigger** | Repo is a Python project (has `.py` files and a project manifest like `pyproject.toml`, `setup.py`, `setup.cfg`, or `requirements.txt`) |
| **Severity** | LOW if no linter configured |
| **What to find** | Presence of any linter configuration: `ruff.toml`, `.ruff.toml`, `.flake8`, `.pylintrc`, `pylintrc`, `pyproject.toml` with `[tool.ruff]`/`[tool.pylint]`/`[tool.flake8]`, `setup.cfg` with `[flake8]`/`[pylint]`, `.pre-commit-config.yaml` referencing ruff/flake8/pylint, or these tools listed as dependencies |
| **Remediation** | Add ruff — fast, comprehensive, replaces flake8+isort+pyflakes. See https://docs.astral.sh/ruff/ |

#### 2.7 Python Type Checker Configuration

| Aspect | Detail |
|--------|--------|
| **Trigger** | Same Python project detection as 2.6 |
| **Severity** | LOW if no type checker configured |
| **What to find** | Presence of any type checker configuration: `mypy.ini`, `.mypy.ini`, `pyrightconfig.json`, `pyrightconfig.yaml`, `pyproject.toml` with `[tool.mypy]`/`[tool.pyright]`/`[tool.pytype]`, `setup.cfg` with `[mypy]`, `.pre-commit-config.yaml` referencing mypy/pyright/pytype, or these tools listed as dependencies |
| **Remediation** | Add mypy or pyright for static type checking to catch bugs early. See https://mypy.readthedocs.io/ |

---

### Dimension 3: Documentation

#### 3.1 README

| Aspect | Detail |
|--------|--------|
| **Severity** | HIGH if missing, HIGH if too thin |
| **Check names** | `README.md`, `README.rst`, `README.txt`, `README` |
| **Substance threshold** | Must have ≥ 500 characters **OR** ≥ 50 lines (flagged only when both are below threshold) |
| **Remediation** | Create/expand with project overview, quick start, usage examples |

#### 3.2 LICENSE

| Aspect | Detail |
|--------|--------|
| **Severity** | HIGH if missing |
| **Check names** | `LICENSE`, `LICENSE.md`, `LICENSE.txt`, `LICENCE`, `LICENCE.md`, `COPYING` |

#### 3.3 CONTRIBUTING.md

| Aspect | Detail |
|--------|--------|
| **Severity** | MEDIUM if missing |

#### 3.4 .gitignore

| Aspect | Detail |
|--------|--------|
| **Severity** | MEDIUM if missing |

#### 3.5 Code of Conduct

| Aspect | Detail |
|--------|--------|
| **Severity** | LOW if missing |
| **Check names** | `CODE_OF_CONDUCT.md`, `CODE_OF_CONDUCT.txt`, `.github/CODE_OF_CONDUCT.md` |

#### 3.6 SECURITY.md

| Aspect | Detail |
|--------|--------|
| **Severity** | MEDIUM if missing |
| **Check names** | `SECURITY.md`, `.github/SECURITY.md` |
| **Why** | Users need a way to report vulnerabilities responsibly |

#### 3.7 CHANGELOG

| Aspect | Detail |
|--------|--------|
| **Severity** | LOW if missing |
| **Check names** | `CHANGELOG.md`, `CHANGELOG.txt`, `CHANGES.md`, `HISTORY.md` |

---

### Dimension 4: Repo Hygiene

#### 4.1 Large Files

| Aspect | Detail |
|--------|--------|
| **Severity** | MEDIUM |
| **Threshold** | > 10 MB |
| **Exclude** | `.git/` directory |
| **Remediation** | Remove or use Git LFS |

#### 4.2 Log Files

| Aspect | Detail |
|--------|--------|
| **Severity** | MEDIUM |
| **Pattern** | `*.log`, `*.log.*` |
| **Remediation** | Remove and add `*.log` to `.gitignore` |

#### 4.3 Data Dumps / Database Exports

| Aspect | Detail |
|--------|--------|
| **Severity** | HIGH |
| **Extensions** | `.sql`, `.dump`, `.bak`, `.csv`, `.sqlite`, `.db` |
| **Threshold** | Only flag files > 1 MB |
| **Exclude** | `*/migrations/*` directory |
| **Remediation** | Remove — may contain sensitive data |

#### 4.4 Build Artifacts

| Aspect | Detail |
|--------|--------|
| **Severity** | MEDIUM |
| **Directories** | `node_modules`, `dist`, `__pycache__`, `.pytest_cache`, `.next`, `.nuxt`, `build`, `target`, `vendor/bundle`, `.gradle`, `bin`, `obj` |
| **Remediation** | Remove and add to `.gitignore` |

#### 4.5 OS-Generated Files

| Aspect | Detail |
|--------|--------|
| **Severity** | LOW |
| **Files** | `.DS_Store`, `Thumbs.db`, `desktop.ini` |
| **Remediation** | Remove and add to `.gitignore` |

#### 4.6 Directory Depth

| Aspect | Detail |
|--------|--------|
| **Severity** | LOW |
| **Threshold** | > 8 levels deep (relative to repo root) |
| **Exclude** | `.git/`, `node_modules/` |
| **Behavior** | Report only the first violation found |
| **Remediation** | Consider flattening directory structure |

---

### Dimension 5: Legal & Compliance

#### 5.1 License Validation

| Aspect | Detail |
|--------|--------|
| **Severity** | HIGH if file exists but license is unrecognized; HIGH if file missing |
| **Method** | Check first 20 lines against known license names |
| **Recognized licenses** | MIT, Apache License, GNU General Public, BSD, ISC, Mozilla Public, Eclipse Public, Unlicense, Creative Commons, LGPL, AGPL, Artistic License, Boost Software |
| **Remediation** | Use a standard SPDX license |

#### 5.2 Internal / Confidential References

| Aspect | Detail |
|--------|--------|
| **Severity** | HIGH |
| **Default keywords** | `internal-only`, `company-confidential`, `do-not-distribute`, `proprietary` |
| **Extensible** | Set `SCAN_INTERNAL_KEYWORDS` env var to add custom keywords (pipe-separated) |
| **Self-exclude** | Skip matches inside the scanner's own scripts |
| **Remediation** | Remove internal references before making repo public |

#### 5.3 Copyright Headers (Sampled)

| Aspect | Detail |
|--------|--------|
| **Severity** | LOW (only if > 50% of sampled files lack headers) |
| **Method** | Sample up to 20 source files, check first 5 lines for `copyright`, `©`, `license`, or `spdx` |
| **File types** | `.py`, `.js`, `.ts`, `.go`, `.java`, `.rb`, `.rs`, `.c`, `.cpp` |
| **Remediation** | Consider adding copyright/license headers |

---

### File Types Scanned Per Check

Different checks scan different file sets. Use this table to understand the exact scope of each check.

| Check | File scope |
|-------|-----------|
| **1.1 .env files** | `find` by filename: `.env`, `.env.*` (excluding `.env.example`, `.env.sample`, `.env.template`) |
| **1.2 Private key files** | `find` by extension/name: `.pem`, `.key`, `.p12`, `.pfx`, `id_rsa`, `id_ed25519`, `id_ecdsa`, `id_dsa` |
| **1.3 Private key content** | All files < 1MB (binary filtered by `file \| grep text`), excluding `.git/`, `node_modules/` |
| **1.4 AWS credentials** | Source + config: `.sh`, `.py`, `.js`, `.ts`, `.go`, `.rb`, `.java`, `.rs`, `.yml`, `.yaml`, `.json`, `.toml`, `.xml`, `.cfg`, `.conf`, `.ini`, `.tf`, `.tfvars`, `.env`, `.env.*` |
| **1.5 Generic secrets** | Same as 1.4 |
| **1.6 Hardcoded IPs** | Same as 1.4 |
| **1.7 PII emails** | Same as 1.4 **plus** `.md`, `.txt`, `.html`, `.xml` |
| **1.8 PII phones** | Same as 1.4 **plus** `.md`, `.txt`, `.html` |
| **1.9 Actions secrets** | `.github/workflows/*.yml`, `*.yaml` only |
| **1.10 Actions injection** | `.github/workflows/*.yml`, `*.yaml` only |
| **1.12 Web3 hex keys** | Same as 1.4 (keyword proximity required) |
| **1.13 BIP-39 mnemonics** | Same as 1.4 (context clue pass); also `.env`, `.env.*`, `.js`, `.ts`, `.json`, `.yaml`, `.yml`, `.toml` (bare sequence pass) |
| **1.14 Solana keypairs** | Same as 1.4 (base58 keyword pass); all `*.json` < 1MB (byte-array pass) |
| **1.15 Keystore/wallet files** | `find` by name: `*.keystore`, `*.wallet`, `UTC--*`; content scan on `*.json` < 1MB |
| **1.16 Hardhat/Foundry config** | `hardhat.config.js`, `hardhat.config.ts`, `foundry.toml` (exact files); accounts array via 1.4 includes |
| **2.1 TODO comments** | `.sh`, `.py`, `.js`, `.ts`, `.jsx`, `.tsx`, `.go`, `.rb`, `.java`, `.rs`, `.c`, `.cpp`, `.h`, `.hpp`, `.css`, `.scss`, `.vue`, `.svelte` |
| **2.2 shellcheck** | `*.sh` only |
| **5.2 Internal references** | `.md`, `.txt`, `.yml`, `.yaml`, `.json`, `.toml`, `.cfg`, `.conf`, `.ini`, `.sh`, `.py`, `.js`, `.ts`, `.go`, `.rb`, `.java`, `.rs` |
| **5.3 Copyright headers** | `.py`, `.js`, `.ts`, `.go`, `.java`, `.rb`, `.rs`, `.c`, `.cpp` |

Checks not listed above use `find` by filename/size/directory (no extension filtering).

**Always excluded directories**: `.git`, `node_modules`, `.claude`

---

## Report Format

The scanner outputs a structured Markdown report. Whether generated by script (Model A) or by an LLM (Model B), the report must follow this structure:

```markdown
# Repo Public Readiness Report

**Repository**: {repo_name}
**Scan Date**: {date}
**Overall Status**: ✅ READY / ⚠️ NEEDS WORK / ❌ NOT READY

## Summary

| Dimension | Status | Critical | High | Medium | Low | Skipped |
|-----------|--------|----------|------|--------|-----|---------|
| Security         | ❌/⚠️/✅ | 0 | 0 | 0 | 0 | 0 |
| Code Quality     | ❌/⚠️/✅ | 0 | 0 | 0 | 0 | 0 |
| Documentation    | ❌/⚠️/✅ | 0 | 0 | 0 | 0 | 0 |
| Repo Hygiene     | ❌/⚠️/✅ | 0 | 0 | 0 | 0 | 0 |
| Legal/Compliance | ❌/⚠️/✅ | 0 | 0 | 0 | 0 | 0 |

## Verdict

- Any CRITICAL finding → ❌ NOT READY (block public release)
- Any HIGH finding → ⚠️ NEEDS WORK (strongly recommend fixing)
- Only MEDIUM/LOW → ✅ READY (with recommendations)

## Detailed Findings

### 🔒 Security
- 🚨 **CRITICAL** `path/to/file:line`: Description
  - Remediation: How to fix

### 📊 Code Quality
(same format)

### 📝 Documentation
(same format)

### 🧹 Repo Hygiene
(same format)

### ⚖️ Legal & Compliance
(same format)

## Recommended Actions
1. **[CRITICAL]** Remediation step (`file`)
2. **[HIGH]** Remediation step (`file`)
(ordered by severity, then by dimension)
```

Severity icons in detailed findings:
- 🚨 CRITICAL
- 🔴 HIGH
- 🟡 MEDIUM
- 🔵 LOW
- ⏭️ SKIPPED

---

## Validation

- The report contains a summary table with all five dimensions and their status.
- Each finding includes file path, line number (where applicable), description, and remediation.
- The overall verdict matches the scoring logic (CRITICAL → NOT READY, HIGH → NEEDS WORK).
- Running the scanner twice on the same repo produces the same results (deterministic).
- For Model B: the LLM should aim to cover all checks listed in the Scan Specification. Checks that cannot be performed (e.g., no access to git history) should be reported as SKIPPED with a reason.

## Common Pitfalls

- **Git history not scanned without gitleaks**: The built-in regex checks only scan the working tree (HEAD). Install `gitleaks` to scan the full git history for secrets.
- **False positives on test fixtures**: Files containing example API keys for testing may trigger secret detection. Review findings before acting.
- **Large repos slow the scan**: Repos with deep `node_modules` or build artifacts will be slow. Clean build artifacts before scanning or let the hygiene check flag them.
- **Symlinks**: The scanner follows symlinks. If the repo contains symlinks to outside directories, results may include external files.
- **Model B coverage gap**: An LLM performing checks without scripts cannot run `shellcheck`, `npm audit`, `pip-audit`, `trivy`, or `gitleaks`. These should be reported as SKIPPED with installation instructions.
- **Internal keywords need customization**: The default confidential keywords (`internal-only`, `company-confidential`, etc.) are generic. Set `SCAN_INTERNAL_KEYWORDS` or tell the LLM your company-specific terms for better coverage.
