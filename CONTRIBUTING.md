# Contributing

## Steps

1. Fork the repository
2. Create a feature branch: `feature/your-skill-name`
3. Copy [SKILL_TEMPLATE.md](SKILL_TEMPLATE.md) to `skills/<your-skill-name>/SKILL.md`
4. Fill in the template — read [SKILL_GUIDE.md](SKILL_GUIDE.md) for format requirements and best practices
5. Add `metadata.yaml` (see [SKILL_GUIDE.md](SKILL_GUIDE.md#nexus-specific-conventions) for schema)
6. Add an entry to `catalog.yaml`
7. Run the repo-public-readiness scanner on the repo: `./skills/repo-public-readiness/scripts/run_scan.sh .`
8. Open a PR describing what real-world problem your Skill solves
