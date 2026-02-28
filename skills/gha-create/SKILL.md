---
name: gha-create
description: "Generates GitHub Actions workflows following elite-level security and efficiency best practices. Use when writing new CI/CD workflows, modifying existing workflows, or reviewing workflows for hardening opportunities. Applies SHA-pinned actions, least-privilege permissions, OIDC authentication, injection prevention, path filtering, native caching, and concurrency control. Do NOT use for non-GitHub-Actions CI/CD systems or general DevOps tasks unrelated to workflow authoring."
license: MIT
compatibility: "Layer 1 (Knowledge): Any AI agent. Layer 2 (Validator): bash 4.0+, grep, awk."
metadata:
  author: PSDN-AI
  version: "0.1.0"
  category: CI/CD & DevOps
  tags:
    - github-actions
    - ci-cd
    - security
    - devops
    - workflow
---

# GHA Create

> Most AI-generated and tutorial-sourced GitHub Actions workflows use mutable tags, omit permissions blocks, hardcode long-lived secrets, and lack concurrency controls. This Skill provides a codified engineering standard that agents follow when authoring workflows, so the output is production-grade from the first draft.

## Table of Contents

- [When Should You Use This?](#when-should-you-use-this)
- [How This Skill Can Be Used](#how-this-skill-can-be-used)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Quick Reference Checklist](#quick-reference-checklist)
- [Pillar 1: Security Best Practices](#pillar-1-security-best-practices)
- [Pillar 2: Efficiency Best Practices](#pillar-2-efficiency-best-practices)
- [Workflow Generation Process](#workflow-generation-process)
- [Validation](#validation)
- [Common Pitfalls](#common-pitfalls)
- [References](#references)

## When Should You Use This?

- You are writing a new GitHub Actions workflow from scratch.
- You are modifying or reviewing an existing workflow for hardening.
- You want to transform a naive workflow into a production-grade pipeline.
- You need a quick reference for GitHub Actions security and efficiency rules.

## How This Skill Can Be Used

| Model | How it works | When to use |
|-------|-------------|-------------|
| **A — Script Execution** | Run `validate_workflow.sh` against a workflow file to check compliance | You have bash and want automated rule checking |
| **B — Knowledge-Driven** | An LLM reads this SKILL.md and applies rules when generating workflows | No bash available, or the LLM is generating workflows from scratch |
| **C — Hybrid** | An LLM generates workflows using this spec, then validates with the script | Best coverage — combines generation with automated checking |

## Prerequisites

**Required** (for Knowledge-Driven mode):
- None — any AI agent can read and apply these rules

**Required** (for Script Execution / Hybrid mode):
- `bash` (4.0+), `grep`, `awk`

## Quick Start

### Knowledge-Driven (Agent reads rules, writes workflows)

```
Generate a CI workflow for my Node.js project following gha-create best practices
```

The agent reads this SKILL.md, applies all 8 rules, and produces a hardened workflow.

### CLI (Validate existing workflows)

```bash
# Validate a single workflow
./skills/gha-create/scripts/validate_workflow.sh .github/workflows/ci.yml

# Validate all workflows in a directory
for f in .github/workflows/*.yml; do
  ./skills/gha-create/scripts/validate_workflow.sh "$f"
done
```

## Quick Reference Checklist

When writing or reviewing a workflow, verify every item:

| ID | Rule | Check |
|----|------|-------|
| S1 | SHA Pinning | Every `uses:` pinned to full 40-char SHA with `# vX.Y.Z` comment |
| S2 | Least-Privilege Permissions | Top-level `permissions: contents: read` present |
| S3 | OIDC Authentication | OIDC preferred over static secrets for cloud auth |
| S4 | Injection Prevention | No `${{ github.event.* }}` in `run:` blocks — map to `env:` first |
| E1 | Path Filtering | Triggers use `paths:` or `paths-ignore:` |
| E2 | Native Caching | Every `setup-*` action has `cache:` parameter enabled |
| E3 | Concurrency Control | `concurrency:` group with `cancel-in-progress: true` |
| E4 | Matrix Optimization | `fail-fast: true` on `strategy.matrix` |

## Pillar 1: Security Best Practices

### S1: SHA Pinning

Every third-party action must be pinned to a full 40-character commit SHA with a trailing version comment.

```yaml
# BAD - mutable tag can be moved to point at malicious code
- uses: actions/checkout@v4

# GOOD - immutable reference with human-readable version comment
- uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
```

**Why**: Tags are mutable Git refs. An attacker who compromises an action repository can move a tag to inject malicious code into every workflow that references it. SHA pins are immutable.

**Exceptions**: Local actions (`uses: ./my-action`) do not need SHA pinning.

See [SECURITY_PRACTICES.md](references/SECURITY_PRACTICES.md#s1-sha-pinning) for edge cases and SHA lookup methods.

### S2: Least-Privilege Permissions

Always include an explicit top-level `permissions:` block. Start restrictive, elevate only at the job level with a justification comment.

```yaml
# BAD - no permissions block (defaults to read-write-all in classic repos)
on: push
jobs:
  build:
    runs-on: ubuntu-latest

# GOOD - explicit least privilege at top level
on: push
permissions:
  contents: read
jobs:
  build:
    runs-on: ubuntu-latest
  deploy:
    permissions:
      contents: read
      packages: write  # Needed to push to GHCR
```

See [SECURITY_PRACTICES.md](references/SECURITY_PRACTICES.md#s2-least-privilege-permissions) for common permission patterns.

### S3: OIDC Authentication

Prefer OpenID Connect (short-lived tokens) over static secrets for cloud provider authentication.

```yaml
# BAD - static long-lived credentials stored as secrets
env:
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

# GOOD - OIDC federation with short-lived token
permissions:
  id-token: write
steps:
  - uses: aws-actions/configure-aws-credentials@8df5847569e6427dd6c4fb1cf565c83acfa8afa7 # v6.0.0
    with:
      role-to-assume: arn:aws:iam::123456789012:role/deploy
      aws-region: us-east-1
```

**Note**: OIDC requires cloud provider configuration. When OIDC is not possible, static secrets are acceptable.

See [SECURITY_PRACTICES.md](references/SECURITY_PRACTICES.md#s3-oidc-authentication) for AWS, GCP, and Azure examples.

### S4: Injection Prevention

Never interpolate untrusted event context directly in `run:` blocks. Map to an environment variable first.

```yaml
# BAD - attacker-controlled input injected directly into shell
- run: echo "Title: ${{ github.event.pull_request.title }}"

# GOOD - map to env, then reference the shell variable
- env:
    PR_TITLE: ${{ github.event.pull_request.title }}
  run: echo "Title: $PR_TITLE"
```

**Dangerous contexts** (attacker-controlled, never use directly in `run:`):
`github.event.issue.title`, `github.event.issue.body`, `github.event.pull_request.title`, `github.event.pull_request.body`, `github.event.pull_request.head.ref`, `github.event.comment.body`, `github.event.review.body`, `github.event.head_commit.message`, `github.event.commits.*.message`, `github.event.commits.*.author.name`, `github.event.pages.*.page_name`

See [SECURITY_PRACTICES.md](references/SECURITY_PRACTICES.md#s4-injection-prevention) for the complete list and alternatives.

## Pillar 2: Efficiency Best Practices

### E1: Path Filtering

Use `paths` or `paths-ignore` on `push` and `pull_request` triggers to skip workflows when only irrelevant files change.

```yaml
# BAD - runs on every push regardless of what changed
on: [push, pull_request]

# GOOD - only runs when source code or dependencies change
on:
  push:
    branches: [main]
    paths: ['src/**', 'package*.json', '.github/workflows/ci.yml']
  pull_request:
    paths: ['src/**', 'package*.json', '.github/workflows/ci.yml']
```

**When to skip path filtering**: Release workflows, security scans, and deployment workflows that must run on every push to main.

See [EFFICIENCY_PRACTICES.md](references/EFFICIENCY_PRACTICES.md#e1-path-filtering) for monorepo patterns.

### E2: Native Caching

Every `setup-*` action should enable its built-in cache parameter instead of using a separate `actions/cache` step.

```yaml
# BAD - separate cache step (verbose, error-prone)
- uses: actions/cache@cdf6c1fa76f9f475f3d7449005a359c84ca0f306 # v5.0.3
  with:
    path: ~/.npm
    key: npm-${{ hashFiles('package-lock.json') }}
- uses: actions/setup-node@6044e13b5dc448c55e2357c09f80417699197238 # v6.2.0
  with:
    node-version: 20

# GOOD - built-in cache (one step, automatic key generation)
- uses: actions/setup-node@6044e13b5dc448c55e2357c09f80417699197238 # v6.2.0
  with:
    node-version: 20
    cache: 'npm'
```

See [EFFICIENCY_PRACTICES.md](references/EFFICIENCY_PRACTICES.md#e2-native-caching) for cache parameters per setup action.

### E3: Concurrency Control

Add a `concurrency` group to kill obsolete runs when new commits are pushed rapidly.

```yaml
# BAD - no concurrency control (stale runs waste minutes)

# GOOD - cancel redundant runs
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

**Exception**: Deployment workflows should use `cancel-in-progress: false` to avoid interrupting an active deploy.

See [EFFICIENCY_PRACTICES.md](references/EFFICIENCY_PRACTICES.md#e3-concurrency-control) for group naming patterns.

### E4: Matrix Optimization

When using `strategy.matrix`, keep `fail-fast: true` (the default) and use `include`/`exclude` to avoid wasting runner minutes on irrelevant combinations.

```yaml
# BAD - fail-fast disabled, all matrix jobs run even after first failure
strategy:
  fail-fast: false
  matrix:
    node-version: [18, 20, 22]

# GOOD - fail-fast enabled, stops early on failure
strategy:
  fail-fast: true
  matrix:
    node-version: [18, 20, 22]
```

See [EFFICIENCY_PRACTICES.md](references/EFFICIENCY_PRACTICES.md#e4-matrix-optimization) for dynamic matrices and `max-parallel`.

## Workflow Generation Process

When generating a GitHub Actions workflow from scratch, follow these steps in order:

1. **Define triggers** — Identify events (`push`, `pull_request`, `workflow_dispatch`). Apply path filtering (E1) unless the workflow must run on every change (e.g., deployments, security scans).

2. **Set top-level permissions** — Add `permissions: contents: read` immediately after the trigger block. Never omit this (S2).

3. **Add concurrency control** — Add a `concurrency:` group with `cancel-in-progress: true` (E3). For deployment workflows, use `cancel-in-progress: false`.

4. **Define jobs** — For each job:
   a. Elevate permissions at the job level only if needed (S2). Add a comment explaining why.
   b. Pin every `uses:` to a full 40-char SHA with a version comment (S1). Use [SHA_LOOKUP.md](references/SHA_LOOKUP.md) or `gh api` to find current SHAs.
   c. Enable native caching on all `setup-*` steps (E2).
   d. Map any untrusted event context to `env:` before using in `run:` blocks (S4).
   e. Use OIDC for cloud provider authentication when possible (S3).

5. **Optimize with matrix** — If testing across versions or platforms, use `strategy.matrix` with `fail-fast: true` (E4). Use `include`/`exclude` to skip unnecessary combinations.

6. **Validate** — Run `validate_workflow.sh` against the output, or manually verify against the [Quick Reference Checklist](#quick-reference-checklist).

## Validation

### Automated Validation

```bash
./skills/gha-create/scripts/validate_workflow.sh <workflow-file>
```

Exit code 0 = all checks pass. Exit code 1 = violations found.

The validator checks all 8 rules (S1-S4, E1-E4). Some rules (S3, E1, E4) are advisory — they produce warnings but do not cause a hard failure.

### Manual Validation

Walk through the [Quick Reference Checklist](#quick-reference-checklist) for each workflow file.

## Common Pitfalls

- **Forgetting the version comment on SHA pins**: `@abc123def...` without `# v4.2.2` is technically compliant but unreadable. Always add the comment so humans can see which version is pinned.
- **Using `permissions: write-all`**: This is worse than omitting the block entirely because it signals intentional over-permissioning. Always enumerate specific permissions.
- **Cancelling deployment workflows**: Setting `cancel-in-progress: true` on a deployment can leave infrastructure in a half-deployed state. Use `cancel-in-progress: false` for deploy jobs.
- **Caching with separate `actions/cache`**: The setup actions (setup-node, setup-python, etc.) have built-in cache support that is simpler and less error-prone. Use the built-in parameter.
- **Path filtering on deployment workflows**: Deployment workflows triggered by pushes to `main` should generally NOT use path filters — you want every merged PR to trigger a deploy.
- **OIDC is not always available**: Self-hosted runners, non-cloud targets, and some organizational policies may prevent OIDC setup. Static secrets are acceptable when OIDC is genuinely not an option. The validator treats this as advisory.
- **Interpolating `github.event.pull_request.number` in `run:`**: Unlike `.title` or `.body`, numeric fields like `.number` are not injection vectors. However, the safest habit is to always map event context to `env:` regardless. The validator flags all dangerous subfields listed in the S4 section.

## References

### Detailed Rule Documentation
- [Security Practices (S1-S4)](references/SECURITY_PRACTICES.md) — Detailed rules, edge cases, and examples
- [Efficiency Practices (E1-E4)](references/EFFICIENCY_PRACTICES.md) — Detailed rules, edge cases, and examples
- [SHA Lookup Guide](references/SHA_LOOKUP.md) — How to find current SHAs for GitHub Actions

### Reference Workflow Templates
- [node-ci.yml](assets/node-ci.yml) — Node.js CI pipeline (S1, S2, E1-E4)
- [docker-build.yml](assets/docker-build.yml) — Docker build and push to GHCR (S1, S2, E1, E3)
- [oidc-deploy.yml](assets/oidc-deploy.yml) — OIDC-based AWS deployment (S1, S2, S3, E3)

### Before/After Examples
- [before.yml](examples/before.yml) — Naive workflow violating all rules
- [after.yml](examples/after.yml) — Same workflow transformed to meet the standard
