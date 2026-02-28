# gha-create

Generate GitHub Actions workflows with elite-level security and efficiency best practices.

## Claude Code

```bash
# Install the plugin
/plugin install gha-create@nexus-skills

# Ask the agent to generate a workflow
Generate a CI workflow for my Node.js project following best practices
```

## CLI

```bash
# Validate a single workflow
./skills/gha-create/scripts/validate_workflow.sh .github/workflows/ci.yml

# Validate all workflows in a directory
for f in .github/workflows/*.yml; do
  ./skills/gha-create/scripts/validate_workflow.sh "$f"
done
```

## GitHub Actions

```yaml
- uses: PSDN-AI/nexus-skills/skills/gha-create@main
  id: validate
  with:
    workflow_dir: ".github/workflows"
```

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `workflow_dir` | No | `.github/workflows` | Directory containing workflow files to validate |

**Outputs:**

| Output | Description |
|--------|-------------|
| `status` | Overall validation status: `PASS` or `FAIL` |
| `violations` | Number of workflow files with violations |

## Full Specification

See [SKILL.md](SKILL.md) for the complete AI agent specification.
