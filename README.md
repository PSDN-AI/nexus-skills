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
```

### Layer 2: CLI

```bash
git clone https://github.com/PSDN-AI/nexus-skills.git
```

### Layer 3: GitHub Actions

```yaml
- uses: PSDN-AI/nexus-skills/skills/<skill-name>@v0.0.1
```

### Layer 1: AI Agent

Point any AI agent (Claude Code, GPT, etc.) to a SKILL.md:

```
Read skills/<skill-name>/SKILL.md and follow the instructions.
```

## Available Skills

### repo-public-readiness

Scan a repo for secrets, quality issues, missing docs, and compliance problems before going public.

```bash
# Claude Code — install & run
/plugin install repo-public-readiness@nexus-skills
Scan this repository for public readiness issues

# CLI
./skills/repo-public-readiness/scripts/run_scan.sh /path/to/repo

# Save report to file
./skills/repo-public-readiness/scripts/run_scan.sh /path/to/repo > report.md
```

```yaml
# GitHub Actions
- uses: PSDN-AI/nexus-skills/skills/repo-public-readiness@v0.0.1
  id: scan
  with:
    repo_path: "."
```

### prd-decomposer

Decompose a PRD into domain-specific specs (frontend, backend, infra, etc.) for AI Agent consumption.

```bash
# Claude Code — install & run
/plugin install prd-decomposer@nexus-skills
Read skills/prd-decomposer/SKILL.md and decompose docs/prd.md

# CLI
./skills/prd-decomposer/scripts/decompose.sh /path/to/prd.md

# Dry run — preview classification without generating files
./skills/prd-decomposer/scripts/decompose.sh /path/to/prd.md --dry-run
```

```yaml
# GitHub Actions
- uses: PSDN-AI/nexus-skills/skills/prd-decomposer@v0.0.1
  with:
    prd-path: "docs/prd.md"
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a new Skill.

## License

[MIT](LICENSE)
