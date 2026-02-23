# Nexus Skills

> *"What real-world problem do you solve?"*
> — Sy Lee, CEO @ Poseidon AI

## What is this?

A curated marketplace of reusable AI Agent Skills for Infrastructure, DevOps, and Automation. Each Skill is a standardized, battle-tested knowledge module that any AI Agent can use.

## How Skills Work

Every Skill can be consumed at three layers:

```
┌─────────────────────────────────────────────────────┐
│  Layer 3: CI/CD (GitHub Actions)                    │
│  uses: PSDN-AI/nexus-skills/skills/...@v0.0.1        │
│  → Automated pipeline integration via action.yml    │
├─────────────────────────────────────────────────────┤
│  Layer 2: CLI (Bash Scripts)                        │
│  ./scanner/run_scan.sh /path/to/repo                │
│  → Direct execution by humans or agents             │
├─────────────────────────────────────────────────────┤
│  Layer 1: AI Knowledge (SKILL.md)                   │
│  AI reads instructions → understands task → acts    │
│  → Any AI agent can consume this, vendor-neutral    │
└─────────────────────────────────────────────────────┘
```

## Quick Start

### Layer 2: CLI

```bash
git clone https://github.com/PSDN-AI/nexus-skills.git
./nexus-skills/skills/repo-public-readiness/scanner/run_scan.sh /path/to/your/repo
```

Save the report:

```bash
./nexus-skills/skills/repo-public-readiness/scanner/run_scan.sh /path/to/your/repo > report.md
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

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a new Skill.

## License

[MIT](LICENSE)
