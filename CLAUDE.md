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

## Project Conventions

**Read [AGENTS.md](AGENTS.md) and follow all rules defined there.** It is the single source of truth for project structure, coding style, naming conventions, commit/PR guidelines, and labeling policy.

Also refer to:

| Document | Covers |
|----------|--------|
| [SKILL_GUIDE.md](SKILL_GUIDE.md) | Skill authoring standard, frontmatter format, progressive disclosure, naming |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution workflow, branch naming, PR process |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Consumption models and cross-repo integration |
| [SKILL_TEMPLATE.md](SKILL_TEMPLATE.md) | Copy-paste starter for new Skills |

## Additional Rules

**Box-drawing diagrams must be pixel-aligned** — use ASCII box characters (`+`, `-`, `|`) and ASCII arrows (`->`) instead of Unicode (`┌│├└`, `→`). Unicode characters render at inconsistent widths across platforms. Every row must have identical total width. Verify with `awk '{ print length, $0 }'` before committing.
