# Nexus Skills

## What is this?

A curated marketplace of reusable AI Agent Skills for Infrastructure, DevOps, and Automation. Each Skill is a standardized, battle-tested knowledge module that any AI Agent can use. Skills follow the [Agent Skills standard](https://agentskills.io) — the open format supported by 30+ agent products.

## How Skills Work

Every Skill can be consumed at three layers:

```
+----------------------------------------------------+
|  Layer 3: CI/CD (GitHub Actions)                   |
|  uses: PSDN-AI/nexus-skills/skills/...@v0.0.1      |
|  -> Automated pipeline integration via action.yml  |
+----------------------------------------------------+
|  Layer 2: CLI (Bash Scripts)                       |
|  ./scripts/run_scan.sh /path/to/repo               |
|  -> Direct execution by humans or agents           |
+----------------------------------------------------+
|  Layer 1: AI Knowledge (SKILL.md)                  |
|  AI reads instructions -> understands task -> acts |
|  -> Any AI agent can consume this, vendor-neutral  |
+----------------------------------------------------+
```

## Prerequisites

- **bash 4.0+** — required for CLI and CI layers (the scanner uses associative arrays)
  - macOS ships bash 3.2; upgrade with `brew install bash`
  - Linux (Ubuntu, Debian, etc.) ships bash 5.x — no action needed
  - CI (GitHub Actions `ubuntu-latest`) — no action needed
- `grep`, `find`, `file`, `wc` — standard POSIX tools (pre-installed everywhere)
- Optional: `gitleaks`, `shellcheck`, `trivy`, `jq` — enhanced checks, gracefully skipped if missing

## Quick Start

### Claude Code (Plugin Marketplace)

```bash
/plugin marketplace add PSDN-AI/nexus-skills
/plugin install repo-public-readiness@nexus-skills
```

### Layer 2: CLI

```bash
git clone https://github.com/PSDN-AI/nexus-skills.git
./nexus-skills/skills/repo-public-readiness/scripts/run_scan.sh /path/to/your/repo
```

Save the report:

```bash
./nexus-skills/skills/repo-public-readiness/scripts/run_scan.sh /path/to/your/repo > report.md
```

### Layer 3: GitHub Actions

```yaml
# .github/workflows/readiness.yml
name: Repo Public Readiness
on: [push, pull_request]
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: PSDN-AI/nexus-skills/skills/repo-public-readiness@v0.0.1
        id: scan
      - run: echo "Status is ${{ steps.scan.outputs.status }}"
```

### Layer 1: AI Agent

Point any AI agent (Claude Code, GPT, etc.) to the SKILL.md:

```
Read skills/repo-public-readiness/SKILL.md and follow the instructions
to scan this repository.
```

## Available Skills

| Skill | Description | Complexity |
|-------|-------------|------------|
| [repo-public-readiness](skills/repo-public-readiness/) | Scan a repo for secrets, quality issues, missing docs, and compliance problems before going public | Intermediate |
| [prd-decomposer](skills/prd-decomposer/) | Decompose a PRD into domain-specific specs (frontend, backend, infra, etc.) for AI Agent consumption | Intermediate |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a new Skill.

## License

[MIT](LICENSE)
