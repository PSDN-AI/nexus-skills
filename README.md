# Nexus Skills

## What is this?

A curated marketplace of reusable AI Agent Skills for Infrastructure, DevOps, and Automation. Each Skill is a standardized, battle-tested knowledge module that any AI Agent can use. Skills follow the [Agent Skills standard](https://agentskills.io) — the open format supported by 30+ agent products.

## How Skills Work

Every Skill can be consumed in three ways:

| Method | How it works |
|--------|-------------|
| **Claude Code** | Install via plugin marketplace, then ask the agent to run the skill |
| **CLI** | Run bash scripts directly from the terminal |
| **GitHub Actions** | Add to CI/CD pipelines via `action.yml` |

## Prerequisites

- **bash 4.0+** — required for CLI and GitHub Actions (scripts use associative arrays)
  - macOS ships bash 3.2; upgrade with `brew install bash`
  - Linux (Ubuntu, Debian, etc.) ships bash 5.x — no action needed
  - CI (GitHub Actions `ubuntu-latest`) — no action needed
- `grep`, `find`, `file`, `wc` — standard POSIX tools (pre-installed everywhere)
- Optional: `gitleaks`, `shellcheck`, `trivy`, `jq` — enhanced checks, gracefully skipped if missing

## Quick Start

### Claude Code

```bash
/plugin marketplace add PSDN-AI/nexus-skills
```

### CLI

```bash
git clone https://github.com/PSDN-AI/nexus-skills.git
```

### GitHub Actions

```yaml
- uses: PSDN-AI/nexus-skills/skills/<skill-name>@main
```

## Available Skills

| Skill | Category | Description |
|-------|----------|-------------|
| [repo-audit](skills/repo-audit/) | Security & Compliance | Scan for secrets, quality issues, and compliance problems before going public |
| [prd-decompose](skills/prd-decompose/) | Product Engineering | Decompose a PRD into domain-specific specs for AI Agent consumption |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a new Skill.

## License

[MIT](LICENSE)
