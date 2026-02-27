# repo-public-readiness

Scan a repo for secrets, quality issues, missing docs, and compliance problems before going public.

## Claude Code

```bash
# Install the plugin
/plugin install repo-public-readiness@nexus-skills

# Ask the agent to scan
Scan this repository for public readiness issues
```

## CLI

```bash
# Scan a repository
./skills/repo-public-readiness/scripts/run_scan.sh /path/to/repo

# Save report to file
./skills/repo-public-readiness/scripts/run_scan.sh /path/to/repo > report.md
```

## GitHub Actions

```yaml
- uses: PSDN-AI/nexus-skills/skills/repo-public-readiness@v0.0.1
  id: scan
  with:
    repo_path: "."
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `repo_path` | No | `.` | Path to the repository to scan |

**Outputs:**

| Output | Description |
|--------|-------------|
| `status` | Overall scan status: `READY`, `NEEDS_WORK`, or `NOT_READY` |
| `report` | Path to the generated Markdown report |

## Full Specification

See [SKILL.md](SKILL.md) for the complete AI agent specification.
