# Repo Public Readiness Scanner

> Before making a repository public, teams need to ensure it contains no secrets, meets quality standards, has proper documentation, and is free of compliance issues. This Skill provides a comprehensive, automated scan with a clear pass/fail report.

## When Should You Use This?

- You are about to make a private repository public on GitHub, GitLab, or any hosting platform.
- You want to audit a repository for accidentally committed secrets, credentials, or internal references.
- You need a pre-release checklist that covers security, code quality, documentation, hygiene, and legal compliance.

## Prerequisites

**Required** (built-in on macOS/Linux):
- `bash` (4.0+)
- `grep`, `find`, `file`, `wc`, `du`, `stat`

**Optional** (enhanced checks when available):
- `gitleaks` — deep secret scanning including git history
- `trufflehog` — additional secret detection patterns
- `shellcheck` — bash script linting
- `trivy` — dependency vulnerability scanning
- `npm` / `pip` — language-specific dependency audits

If an optional tool is not installed, the scanner reports the check as **SKIPPED** rather than failing.

## Instructions

1. Clone or navigate to the target repository.
2. Run the scanner:
   ```bash
   ./skills/repo-public-readiness/scanner/run_scan.sh /path/to/target/repo
   ```
3. The scanner executes five check modules in sequence:
   - **Security** — secrets, keys, credentials, .env files
   - **Code Quality** — linting, TODO comments, dependency vulnerabilities
   - **Documentation** — README, LICENSE, CONTRIBUTING, .gitignore
   - **Repo Hygiene** — large files, build artifacts, log files, directory depth
   - **Legal & Compliance** — license validation, internal references
4. A Markdown report is generated to stdout (pipe to file if needed):
   ```bash
   ./scanner/run_scan.sh /path/to/repo > report.md
   ```
5. Review the report. The overall verdict is:
   - **NOT READY** — any CRITICAL finding exists (block release)
   - **NEEDS WORK** — any HIGH finding exists (strongly recommend fixing)
   - **READY** — only MEDIUM/LOW findings (minor recommendations)

## Validation

- The report contains a summary table with all five dimensions and their status.
- Each finding includes file path, line number (where applicable), description, and remediation.
- The overall verdict matches the scoring logic (CRITICAL → NOT READY, HIGH → NEEDS WORK).
- Running the scanner twice on the same repo produces the same results (deterministic).

## Common Pitfalls

- **Git history not scanned without gitleaks**: The built-in regex checks only scan the working tree (HEAD). Install `gitleaks` to scan the full git history for secrets.
- **False positives on test fixtures**: Files containing example API keys for testing may trigger secret detection. Review findings before acting.
- **Large repos slow the scan**: Repos with deep `node_modules` or build artifacts will be slow. Clean build artifacts before scanning or let the hygiene check flag them.
- **Symlinks**: The scanner follows symlinks. If the repo contains symlinks to outside directories, results may include external files.
