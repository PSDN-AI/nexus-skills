# Nexus Skills

> *"What real-world problem do you solve?"*
> — Sy Lee, CEO @ Poseidon AI

## What is this?

A curated marketplace of reusable AI Agent Skills for Infrastructure, DevOps, and Automation. Each Skill is a standardized, battle-tested knowledge module that any AI Agent can use.

## Quick Start

Run the Repo Public Readiness Scanner on any repository:

```bash
git clone https://github.com/PSDN-AI/nexus-skills.git
cd nexus-skills
./skills/repo-public-readiness/scanner/run_scan.sh /path/to/your/repo
```

Pipe to a file for a persistent report:

```bash
./skills/repo-public-readiness/scanner/run_scan.sh /path/to/your/repo > report.md
```

## Available Skills

| Skill | Description | Complexity |
|-------|-------------|------------|
| [repo-public-readiness](skills/repo-public-readiness/) | Scan a repo for secrets, quality issues, missing docs, and compliance problems before going public | Intermediate |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a new Skill.

## License

[MIT](LICENSE)
