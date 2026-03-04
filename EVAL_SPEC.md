# Eval Specification

This document defines the YAML format for agent-effectiveness evaluations in Nexus Skills. Evals measure whether a Skill **as a whole** produces good outcomes when an agent uses it --- they complement `tests/`, which validate script correctness.

Inspired by [Anthropic's skill-creator eval guide](https://claude.com/blog/improving-skill-creator-test-measure-and-refine-agent-skills).

---

## Table of Contents

- [Tests vs Evals](#tests-vs-evals)
- [YAML Schema](#yaml-schema)
- [Field Reference](#field-reference)
- [Writing Good Prompts](#writing-good-prompts)
- [Writing Good Success Criteria](#writing-good-success-criteria)
- [Tag Taxonomy](#tag-taxonomy)
- [Examples](#examples)

---

## Tests vs Evals

| Property | `tests/` | `evals/` |
|----------|----------|----------|
| What it validates | Script correctness | Skill effectiveness |
| Deterministic? | Yes | No --- LLM output varies |
| Runs in CI? | Yes | No --- requires an LLM |
| Requires LLM? | No | Yes |
| File pattern | `test_*.sh` | `eval_*.yaml` |
| Entry point | `run_tests.sh` | Manual or eval harness |
| Pass/fail criteria | Exit code | Human or LLM judgment against `expected` |
| Typical runtime | Seconds | Minutes |

Both directories are optional. Skills with scripts should have `tests/`. All non-trivial Skills should have `evals/`.

---

## YAML Schema

### Minimal Example

```yaml
prompt: |
  Scan the repository at /tmp/test-repo for secrets and
  generate a readiness report.
expected:
  - "Report contains an overall READY or NOT READY verdict"
  - "All five scan dimensions are listed in the summary table"
```

### Full Example

```yaml
prompt: |
  Scan the repository at /tmp/test-repo for secrets and
  generate a readiness report.
description: >
  Verify that the scanner produces a complete report with correct
  verdicts when pointed at a clean repository.
tags:
  - basic
  - happy-path
context_files:
  - skills/repo-audit/SKILL.md
  - skills/repo-audit/references/SCAN_SPEC.md
setup: |
  mkdir -p /tmp/test-repo
  cd /tmp/test-repo && git init
  echo "# Hello" > README.md && echo "MIT" > LICENSE
  git add -A && git commit -m "init"
expected:
  - "Report contains an overall READY verdict"
  - "All five scan dimensions appear in the summary table"
  - "No CRITICAL or HIGH findings are reported"
expected_behavior:
  verdict: READY
  dimensions_present:
    - Security
    - Code Quality
    - Documentation
    - Repo Hygiene
    - Legal & Compliance
  critical_findings: 0
  high_findings: 0
difficulty: basic
model_agnostic: true
notes: >
  The clean repo may still produce LOW findings for missing
  CONTRIBUTING.md or CHANGELOG.md depending on the scan spec version.
```

---

## Field Reference

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `prompt` | string | The prompt to give the agent. Should be self-contained --- an evaluator pastes this into an agent session verbatim. |
| `expected` | list of strings | Success criteria in plain English. Each item is one pass/fail criterion the evaluator checks against the agent's output. |

### Optional Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `description` | string | --- | Human-readable summary of what this eval tests and why. |
| `tags` | list of strings | `[]` | Classification tags from the [tag taxonomy](#tag-taxonomy). |
| `context_files` | list of strings | `[]` | Paths (relative to repo root) the agent should load before executing. |
| `setup` | string | --- | Shell commands to run before the eval to prepare the environment (create temp repos, seed data, etc.). |
| `expected_behavior` | map | --- | Structured, machine-parseable success criteria for automated eval harnesses. Keys are free-form. Only add this when building a harness that scores programmatically --- it should express the same intent as `expected`. |
| `difficulty` | string | --- | One of: `basic`, `intermediate`, `advanced`. |
| `model_agnostic` | boolean | `true` | Whether the eval is designed to work across different LLMs. Set to `false` if it relies on model-specific capabilities. |
| `notes` | string | --- | Additional context for eval runners --- known edge cases, expected variance, etc. |

### Field Constraints

- `prompt` must be non-empty.
- `expected` must contain at least one criterion.
- `tags` values should come from the [tag taxonomy](#tag-taxonomy) but custom tags are allowed.
- `context_files` paths are relative to the repository root.
- `setup` commands must be self-cleaning. Use `rm -rf` at the top to remove prior state from the same eval.
- `difficulty` must be one of `basic`, `intermediate`, `advanced` if present.

---

## Writing Good Prompts

### Be Specific

Bad:
```yaml
prompt: "Audit this repo."
```

Good:
```yaml
prompt: |
  Scan the repository at /tmp/test-repo using the repo-audit
  skill. Generate a Markdown readiness report covering all five
  scan dimensions (Security, Code Quality, Documentation, Repo
  Hygiene, Legal & Compliance). Include an overall verdict.
```

### Include Context the Agent Needs

If the eval depends on a specific repository state, describe it or use `setup` to create it:

```yaml
setup: |
  mkdir -p /tmp/test-repo
  cd /tmp/test-repo && git init
  echo "AWS_SECRET_KEY=AKIAIOSFODNN7EXAMPLE" > config.py
  git add -A && git commit -m "init"
prompt: |
  Scan the repository at /tmp/test-repo for secrets.
  The repo intentionally contains a hardcoded AWS key.
```

### Match the Consumption Model

Write prompts that match how agents actually use the Skill:

- **Model A (Script Execution)**: "Run `scripts/run_scan.sh /tmp/test-repo` and interpret the output."
- **Model B (Knowledge-Driven)**: "Read the scan specification and perform the checks using your own tools."
- **Model C (Hybrid)**: "Run the scan script, then review the findings and suggest remediations."

---

## Writing Good Success Criteria

### Use Observable Outcomes

Each `expected` item should describe something an evaluator can verify by reading the agent's output.

Bad:
```yaml
expected:
  - "The agent understands the report"
```

Good:
```yaml
expected:
  - "Report contains an overall READY or NOT READY verdict"
  - "Each finding includes file path, severity, and remediation"
```

### Be Exhaustive but Reasonable

Cover the key outcomes without being so specific that normal LLM variation causes false failures:

```yaml
expected:
  - "AWS_SECRET_KEY in config.py is identified as a CRITICAL finding"
  - "Overall verdict is NOT READY"
  - "Remediation suggests removing the key and rotating credentials"
```

### Use `expected_behavior` for Automation

When evals will be scored by a harness rather than a human, add structured criteria:

```yaml
expected_behavior:
  verdict: NOT_READY
  must_find_files:
    - config.py
  minimum_critical_findings: 1
```

---

## Tag Taxonomy

| Tag | When to use |
|-----|-------------|
| `basic` | Core functionality, happy-path scenarios |
| `intermediate` | Multi-step workflows, combined features |
| `advanced` | Complex scenarios, edge cases requiring deep reasoning |
| `happy-path` | Expected, common-case input |
| `edge-case` | Unusual input, boundary conditions |
| `regression` | Previously broken behavior that was fixed |
| `security` | Security-related checks |
| `knowledge-only` | Eval that uses Model B (no script execution) |
| `script-execution` | Eval that uses Model A (script execution only) |
| `hybrid` | Eval that uses Model C (scripts + knowledge) |
| `web3` | Web3/blockchain-specific checks |

Custom tags are allowed. Keep them lowercase, hyphen-separated.

---

## Examples

### Script Execution Eval (Model A)

```yaml
prompt: |
  Run the repo-audit scan script against /tmp/test-repo:
    ./skills/repo-audit/scripts/run_scan.sh /tmp/test-repo
  Report the overall verdict and list any CRITICAL findings.
description: >
  Verify the scan script produces correct output when executed
  directly by the agent.
tags:
  - basic
  - script-execution
setup: |
  mkdir -p /tmp/test-repo
  cd /tmp/test-repo && git init
  echo "# My Project" > README.md && echo "MIT" > LICENSE
  git add -A && git commit -m "init"
expected:
  - "Script executes without errors"
  - "Output contains a Markdown-formatted report"
  - "Overall verdict is READY"
difficulty: basic
```

### Knowledge-Driven Eval (Model B)

```yaml
prompt: |
  Without running any scripts, read the repo-audit scan
  specification and perform a manual security audit of the
  repository at /tmp/test-repo. Report findings in the same
  format as the scan script output.
description: >
  Verify that an agent can perform a comprehensive audit using
  only the skill's documentation and its own tools.
tags:
  - intermediate
  - knowledge-only
context_files:
  - skills/repo-audit/SKILL.md
  - skills/repo-audit/references/SCAN_SPEC.md
  - skills/repo-audit/references/REPORT_FORMAT.md
setup: |
  mkdir -p /tmp/test-repo
  cd /tmp/test-repo && git init
  echo "password = 's3cret'" > app.py
  echo "# My App" > README.md
  git add -A && git commit -m "init"
expected:
  - "Hardcoded password in app.py is identified"
  - "Report covers all five scan dimensions"
  - "Checks the agent cannot perform are marked SKIPPED"
difficulty: intermediate
```

### Hybrid Eval (Model C)

```yaml
prompt: |
  Run the repo-audit scan script on /tmp/test-repo, then review
  the findings. For each CRITICAL or HIGH finding, provide a
  specific remediation with code examples.
description: >
  Verify the agent can execute the scan and add value by
  interpreting and extending the automated results.
tags:
  - intermediate
  - hybrid
setup: |
  mkdir -p /tmp/test-repo
  cd /tmp/test-repo && git init
  echo "GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" > deploy.sh
  echo "# Deploy" >> deploy.sh
  chmod +x deploy.sh
  git add -A && git commit -m "init"
expected:
  - "Scan script runs successfully"
  - "GITHUB_TOKEN in deploy.sh is flagged as CRITICAL"
  - "Remediation includes using environment variables or a secrets manager"
  - "Code example shows how to replace the hardcoded token"
difficulty: intermediate
```

---

## File Naming

Eval files follow the pattern `eval_<descriptive_name>.yaml`:

- `eval_clean_repo_scan.yaml`
- `eval_secrets_detected.yaml`
- `eval_knowledge_driven_scan.yaml`

Use snake_case for the descriptive name. This mirrors the `test_*.sh` convention in `tests/`.

---

## Running Evals

Evals are **not** run in CI. They require an LLM and produce non-deterministic results.

To run an eval manually:

1. Execute the `setup` commands (if any) to prepare the environment.
2. Load the `context_files` (if any) into the agent session.
3. Give the agent the `prompt` verbatim.
4. Compare the agent's output against each `expected` criterion.
5. Score each criterion as pass or fail.

A future eval harness may automate steps 2--5. The `expected_behavior` field supports this by providing structured, machine-parseable criteria.
