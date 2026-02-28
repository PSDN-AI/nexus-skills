# Contributing

## Steps

1. Fork the repository
2. Create a feature branch: `feature/your-skill-name`
3. Copy [SKILL_TEMPLATE.md](SKILL_TEMPLATE.md) to `skills/<your-skill-name>/SKILL.md`
4. Fill in the template — read [SKILL_GUIDE.md](SKILL_GUIDE.md) for format requirements and best practices
5. Run the repo-audit scanner on the repo: `./skills/repo-audit/scripts/run_scan.sh .`
   - **Note**: Running on this repo will report ❌ NOT READY — this is expected. The scanner detects fake secrets and internal keywords in test fixtures (`tests/test_check_secrets.sh`, `tests/test_check_compliance.sh`). Review the report to confirm all findings come from test files only.
6. Open a PR describing what real-world problem your Skill solves

## Issue and PR Labels

Apply labels when you open an issue or pull request if you have permission. If you do not have permission, add the intended labels to the description so a maintainer can apply them.

Required labels:
- Every issue: at least one of `bug`, `enhancement`, `documentation`, `question`, or `security`
- Every pull request: at least one type label plus one scope label (`new-skill`, `area:repo`, `area:ci`, `area:docs`) or one skill label (`skill:repo-audit`, `skill:prd-decompose`, `skill:gha-create`)

Additional rules:
- New skill proposals and new skill pull requests must include `new-skill`
- Use `skill:<name>` only when one skill is the primary focus of the change
- `status:needs-review` and `status:blocked` are optional workflow labels
- Do not use legacy labels for new work: `skill:repo-public-readiness`, `skill:github-actions-hardening`, `skill:github-actions-standard`, and `skill:github-actions-pro`
