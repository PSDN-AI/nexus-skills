# Repository Guidelines

## Project Structure & Module Organization
Top-level files define repository standards: `README.md`, `CONTRIBUTING.md`, `SKILL_TEMPLATE.md`, `SKILL_GUIDE.md`, and `CLAUDE.md`.
All skills live in `skills/<skill-name>/` (lowercase kebab-case). Each skill must include:
- `SKILL.md` (YAML frontmatter + instructions)

Current skills:
- `skills/repo-audit/` (repository readiness scanner)
- `skills/prd-decompose/` (PRD decomposition workflow)
- `skills/gha-create/` (GitHub Actions workflow generator and validator)

Standard skill layout (recommended):
- `scripts/` for executable workflows
- `references/` for detailed docs loaded on demand
- `assets/` for templates or data files
- `examples/` for expected outputs
- `tests/` with `run_tests.sh` as entry point
- `action.yml` for GitHub Actions integration

## Build, Test, and Development Commands
- `./skills/repo-audit/scripts/run_scan.sh /path/to/repo`  
Runs the full public-readiness scan and prints a Markdown report.
- `./skills/repo-audit/scripts/run_scan.sh .`  
Validates this repository (recommended before opening a PR).
- `./skills/prd-decompose/scripts/decompose.sh <prd_path> --dry-run`  
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
- Skill names: noun-verb pattern (`repo-audit`, `prd-decompose`) — two words, lowercase kebab-case
- Script files: snake_case (`run_scan.sh`)
- YAML keys: snake_case
- SKILL frontmatter `name` must match directory name exactly

Prefer macOS/Linux-compatible tooling (`grep`, `find`, `file`). Optional tools should degrade gracefully to `SKIPPED`, not hard failures.

## Testing Guidelines
Validation is skill-specific and execution-based:
1. Run `bash skills/<skill-name>/tests/run_tests.sh` for every changed skill.
2. Run `./skills/repo-audit/scripts/run_scan.sh .` before opening a PR. Note: this repo will report ❌ NOT READY due to intentional fake secrets in test fixtures — verify all findings come from test files only.
3. Re-run deterministic workflows (for example scanner checks) to verify stable output.

When output formats change, update sample artifacts under the skill's `examples/` directory.

## Commit & Pull Request Guidelines
Use concise, imperative commit messages (for example, `Add .gitignore with CLAUDE.md and Agents.md`).  
For contributions, follow `feature/<skill-name>` branch naming from `CONTRIBUTING.md`.

PRs should include:
- Problem statement (what real-world issue the change solves)
- Summary of files changed
- Validation evidence (commands run and key output)

## Issue & PR Labeling Policy
All issues and pull requests should be labeled. Apply labels when opening the item if you have permission; otherwise, list the intended labels in the description so a maintainer can apply them.

Allowed labels:
- Type labels (required on every issue and PR): `bug`, `enhancement`, `documentation`, `question`, `security`
- Scope labels (use one when applicable): `new-skill`, `area:repo`, `area:ci`, `area:docs`
- Skill labels (use one when a single skill is the primary subject): `skill:repo-audit`, `skill:prd-decompose`, `skill:gha-create`
- Status labels (optional): `status:needs-review`, `status:blocked`

Rules:
- Every issue must have at least one type label.
- Every pull request must have at least one type label and one scope or skill label.
- New skill proposals and new skill pull requests must include `new-skill`.
- Use exactly one `skill:<name>` label when the work primarily affects a single skill.

## Security & Configuration Tips
Never commit secrets, private keys, or `.env` files.  
Use `SCAN_INTERNAL_KEYWORDS` to extend internal-reference detection during compliance scans.
