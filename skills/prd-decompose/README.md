# prd-decompose

Decompose a PRD into domain-specific specs (frontend, backend, infra, etc.) for AI Agent consumption.

## Claude Code

```bash
# Install the plugin
/plugin install prd-decompose@nexus-skills

# Ask the agent to decompose a PRD
Read skills/prd-decompose/SKILL.md and decompose docs/prd.md
```

## CLI

```bash
# Decompose a PRD
./skills/prd-decompose/scripts/decompose.sh /path/to/prd.md

# Dry run — preview classification without generating files
./skills/prd-decompose/scripts/decompose.sh /path/to/prd.md --dry-run
```

## GitHub Actions

```yaml
- uses: PSDN-AI/nexus-skills/skills/prd-decompose@main
  with:
    prd-path: "docs/prd.md"
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `prd-path` | Yes | — | Path to the PRD file (`.md` or `.txt`) |
| `output-path` | No | `./prd-output` | Output directory for decomposed specs |
| `taxonomy` | No | — | Path to custom domain taxonomy YAML |

**Outputs:**

| Output | Description |
|--------|-------------|
| `status` | Decomposition status: `success`, `warning`, or `error` |
| `domains` | Comma-separated list of identified domains |
| `coverage` | PRD coverage percentage |
| `warnings` | Number of warnings generated |

## Full Specification

See [SKILL.md](SKILL.md) for the complete AI agent specification.
