# Repository Guidelines

## Project Structure & Module Organization
Top-level files define repository standards: `README.md`, `CONTRIBUTING.md`, `SKILL_TEMPLATE.md`, `SKILL_GUIDE.md`, and `CLAUDE.md`.
All skills live in `skills/<skill-name>/` (lowercase kebab-case). Each skill must include:
- `SKILL.md` (YAML frontmatter + instructions)

The current reference skill is `skills/repo-public-readiness/`:
- `scripts/` for executable checks (`run_scan.sh`, `check_*.sh`)
- `assets/` for reusable report formats
- `examples/` for expected outputs

## Build, Test, and Development Commands
- `./skills/repo-public-readiness/scripts/run_scan.sh /path/to/repo`  
Runs the full public-readiness scan and prints a Markdown report.
- `./skills/repo-public-readiness/scripts/run_scan.sh .`  
Validates this repository (recommended before opening a PR).
- `shellcheck skills/repo-public-readiness/scripts/*.sh`  
Lints Bash scripts used by scanner modules.
- `bash -n skills/repo-public-readiness/scripts/*.sh`  
Fast syntax check when `shellcheck` is unavailable.

## Coding Style & Naming Conventions
Use portable Bash (`#!/usr/bin/env bash`) with `set -euo pipefail`. Scripts must accept target paths as arguments; do not hardcode local paths.  
Naming rules:
- Skill directories: kebab-case (`repo-public-readiness`)
- Script files: snake_case (`run_scan.sh`)
- YAML keys: snake_case

Prefer macOS/Linux-compatible tooling (`grep`, `find`, `file`). Optional tools should degrade gracefully to `SKIPPED`, not hard failures.

## Testing Guidelines
There is no formal unit test suite yet; validation is execution-based:
1. Run `run_scan.sh` against this repo and a sample target repo.
2. Confirm report sections, severity counts, and final verdict logic.
3. Re-run the same scan and verify deterministic output.

When changing scanner logic, include at least one sample report update under `skills/repo-public-readiness/examples/` if output format changes.

## Commit & Pull Request Guidelines
Use concise, imperative commit messages (for example, `Add .gitignore with CLAUDE.md and Agents.md`).  
For contributions, follow `feature/<skill-name>` branch naming from `CONTRIBUTING.md`.

PRs should include:
- Problem statement (what real-world issue the change solves)
- Summary of files changed
- Validation evidence (commands run and key output)
- Validation evidence (scanner output)

## Security & Configuration Tips
Never commit secrets, private keys, or `.env` files.  
Use `SCAN_INTERNAL_KEYWORDS` to extend internal-reference detection during compliance scans.
