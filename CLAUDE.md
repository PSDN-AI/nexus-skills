# CLAUDE.md

## Project Overview

**Nexus** is an open-source ecosystem of reusable AI Agent Skills for Infrastructure, DevOps, and Automation.

| Repo | Purpose |
|------|---------|
| `PSDN-AI/nexus-skills` | Skills Marketplace — curated, standardized, reusable knowledge modules |
| `PSDN-AI/nexus-agents` | Professional Agents — orchestrators that compose multiple Skills |

### Core Principles

1. **Problem-first**: Every Skill must answer "What real-world problem do you solve?" in one sentence.
2. **Fully generic**: No company-specific logic, secrets, or internal references.
3. **Focus**: Make each Skill production-grade and battle-tested before expanding.
4. **Self-bootstrapping**: Use repo-audit to validate this repo before releases.

## Key References

| Document | Covers |
|----------|--------|
| [AGENTS.md](AGENTS.md) | Project structure, build/test commands, coding style, naming, commits, labeling |
| [SKILL_GUIDE.md](SKILL_GUIDE.md) | Skill authoring standard, frontmatter format, progressive disclosure, naming |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution workflow, branch naming, PR process |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Consumption models and cross-repo integration |
| [SKILL_TEMPLATE.md](SKILL_TEMPLATE.md) | Copy-paste starter for new Skills |

## Commit & PR Naming Convention

This project follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

- **Branch**: `<type>/<short-description>` — e.g. `feat/docker-lint-skill`, `fix/exit-code-in-run-scan`
- **Commit**: `<type>: <imperative description>` — e.g. `feat: Add docker-lint skill`
- **PR title**: same as commit format — e.g. `docs: Add Conventional Commits naming convention`

Allowed types: `feat`, `fix`, `docs`, `ci`, `refactor`, `test`, `chore`

## Additional Rules

**Box-drawing diagrams must be pixel-aligned** — use ASCII box characters (`+`, `-`, `|`) and ASCII arrows (`->`) instead of Unicode (`┌│├└`, `→`). Unicode characters render at inconsistent widths across platforms. Every row must have identical total width. Verify with `awk '{ print length, $0 }'` before committing.

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
