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
- uses: PSDN-AI/nexus-skills/skills/gha-create@<full-commit-sha>
  id: validate
  with:
    workflow_dir: ".github/workflows"
    fail_on_violations: "true"
```

Replace `<full-commit-sha>` with the exact commit you want to trust. Avoid mutable refs such as `@main`.

**Inputs:**

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `workflow_dir` | No | `.github/workflows` | Directory containing workflow files to validate |
| `fail_on_violations` | No | `"true"` | Exit non-zero when any workflow file fails validation |

**Outputs:**

| Output | Description |
|--------|-------------|
| `status` | Overall validation status: `PASS` or `FAIL` |
| `violations` | Number of workflow files with violations |

## Full Specification

See [SKILL.md](SKILL.md) for the complete AI agent specification.
