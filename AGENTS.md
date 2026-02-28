# Repository Guidelines

## Project Structure & Module Organization
Top-level files define repository standards: `README.md`, `CONTRIBUTING.md`, `SKILL_TEMPLATE.md`, `SKILL_GUIDE.md`, and `CLAUDE.md`.
All skills live in `skills/<skill-name>/` (lowercase kebab-case). Each skill must include:
- `SKILL.md` (YAML frontmatter + instructions)

Current skills:
- `skills/repo-public-readiness/` (repository readiness scanner)
- `skills/prd-decomposer/` (PRD decomposition workflow)

Standard skill layout (recommended):
- `scripts/` for executable workflows
- `references/` for detailed docs loaded on demand
- `assets/` for templates or data files
- `examples/` for expected outputs
- `tests/` with `run_tests.sh` as entry point
- `action.yml` for GitHub Actions integration

## Build, Test, and Development Commands
- `./skills/repo-public-readiness/scripts/run_scan.sh /path/to/repo`  
Runs the full public-readiness scan and prints a Markdown report.
- `./skills/repo-public-readiness/scripts/run_scan.sh .`  
Validates this repository (recommended before opening a PR).
- `./skills/prd-decomposer/scripts/decompose.sh <prd_path> --dry-run`  
Validates PRD parsing/classification without writing output files.
- `bash skills/<skill-name>/tests/run_tests.sh`  
Runs the test suite for a specific skill.
- `shellcheck skills/<skill-name>/scripts/*.sh`  
Lints production Bash scripts.
- `shellcheck -S warning skills/<skill-name>/tests/*.sh`  
Lints test scripts with relaxed severity.
- `bash -n skills/<skill-name>/scripts/*.sh`  
Fast syntax check when `shellcheck` is unavailable.

## Coding Style & Naming Conventions
Use portable Bash (`#!/usr/bin/env bash`) with `set -euo pipefail`. Scripts must accept target paths as arguments; do not hardcode local paths.
Require Bash 4.0+ when associative arrays are used.  
Naming rules:
- Skill directories: kebab-case (`repo-public-readiness`)
- Script files: snake_case (`run_scan.sh`)
- YAML keys: snake_case
- SKILL frontmatter `name` must match directory name exactly

Prefer macOS/Linux-compatible tooling (`grep`, `find`, `file`). Optional tools should degrade gracefully to `SKIPPED`, not hard failures.

## Testing Guidelines
Validation is skill-specific and execution-based:
1. Run `bash skills/<skill-name>/tests/run_tests.sh` for every changed skill.
2. Run `./skills/repo-public-readiness/scripts/run_scan.sh .` before opening a PR.
3. Re-run deterministic workflows (for example scanner checks) to verify stable output.

When output formats change, update sample artifacts under the skill's `examples/` directory.

## Commit & Pull Request Guidelines
Use concise, imperative commit messages (for example, `Add .gitignore with CLAUDE.md and Agents.md`).  
For contributions, follow `feature/<skill-name>` branch naming from `CONTRIBUTING.md`.

PRs should include:
- Problem statement (what real-world issue the change solves)
- Summary of files changed
- Validation evidence (commands run and key output)

## Security & Configuration Tips
Never commit secrets, private keys, or `.env` files.  
Use `SCAN_INTERNAL_KEYWORDS` to extend internal-reference detection during compliance scans.
