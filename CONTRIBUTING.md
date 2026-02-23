# Contributing to Nexus Skills

Thank you for your interest in contributing! This guide explains how to add a new Skill to the marketplace.

## Adding a New Skill

1. **Copy the template**: Use [SKILL_TEMPLATE.md](SKILL_TEMPLATE.md) as your starting point.
2. **Create a directory**: Add your Skill under `skills/<skill-name>/` using lowercase kebab-case.
3. **Required files**:
   - `SKILL.md` — The core knowledge document (follow the template structure exactly)
   - `metadata.yaml` — Machine-readable metadata
4. **Optional files**:
   - `scanner/` or `scripts/` — Automation scripts
   - `templates/` — Output templates
   - `examples/` — Example outputs or usage
5. **Update `catalog.yaml`**: Add your Skill entry to the registry.
6. **Open a Pull Request**: Describe what problem your Skill solves.

## Skill Requirements

Every Skill **must**:

- Answer "What real-world problem do you solve?" in one sentence
- Be fully generic — no company-specific logic, secrets, or internal references
- Work without paid dependencies (optional tools can enhance, but core must work without them)
- Include validation steps so users can verify correct execution
- Document common pitfalls

## Naming Conventions

- Directory names: lowercase, kebab-case (`repo-public-readiness`)
- Script names: snake_case (`run_scan.sh`)
- YAML keys: snake_case
- No abbreviations unless universally understood (`eks`, `ci-cd`)

## Code Standards

- Run `shellcheck` on all bash scripts
- No hardcoded paths — accept target paths as arguments
- Prefer portable tools (macOS + Linux compatible)
- Gracefully degrade when optional tools are not installed (report as SKIPPED, not fail)
- Output in Markdown format

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`feature/your-skill-name`)
3. Add your Skill following the structure above
4. Run the repo-public-readiness scanner on the repo to validate
5. Open a PR with a clear description of what problem the Skill solves
