# Contributing

## Setup

Enable the pre-commit hook to run shellcheck on staged bash scripts:

```bash
git config core.hooksPath .githooks
```

## Steps

1. Fork the repository
2. Create a feature branch: `feature/your-skill-name`
3. Copy [SKILL_TEMPLATE.md](SKILL_TEMPLATE.md) to `skills/<your-skill-name>/SKILL.md`
4. Fill in the template — read [SKILL_GUIDE.md](SKILL_GUIDE.md) for format requirements and best practices
5. Run the repo-audit scanner on the repo: `./skills/repo-audit/scripts/run_scan.sh .`
   - **Note**: Running on this repo will report ❌ NOT READY — this is expected. The scanner detects fake secrets and internal keywords in test fixtures (`tests/test_check_secrets.sh`, `tests/test_check_compliance.sh`). Review the report to confirm all findings come from test files only.
6. Open a PR describing what real-world problem your Skill solves
