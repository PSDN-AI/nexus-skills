# ARCHITECTURE.md — Nexus Consumption Model

## Core Principle

A Skill is a **knowledge document first, executable second**.

`SKILL.md` is the product — not documentation about the product. An AI Agent reads SKILL.md, understands the task, and executes it using its own tools. Scripts are a convenience layer for automation, not a requirement.

## Three-Layer Consumption Model

```
┌────────────────────────────────────────────────────┐
│  Layer 3: CI/CD (GitHub Actions)                   │
│  uses: PSDN-AI/nexus-skills/skills/...@main        │
│  → Automated pipeline integration via action.yml   │
├────────────────────────────────────────────────────┤
│  Layer 2: CLI (Bash Scripts)                       │
│  ./scanner/run_scan.sh /path/to/repo               │
│  → Direct execution by humans or agents            │
├────────────────────────────────────────────────────┤
│  Layer 1: AI Knowledge (SKILL.md)                  │
│  AI reads instructions → understands task → acts   │
│  → Any AI agent can consume this, vendor-neutral   │
└────────────────────────────────────────────────────┘
```

Each layer wraps the one below it. SKILL.md is always the source of truth.

### Layer 1: AI Knowledge

The foundational layer. SKILL.md contains step-by-step instructions that any AI Agent (Claude, GPT, Gemini, etc.) can read and follow. No scripts are required — the AI uses its own tools to execute the instructions described in SKILL.md.

**Consumption**: AI Agent reads SKILL.md content via file read, URL fetch, or inline context.

### Layer 2: CLI

Pre-built bash scripts that automate the instructions in SKILL.md. Useful for humans running scans manually, or for AI Agents that prefer to delegate to a script rather than executing step-by-step.

**Consumption**: `./scanner/run_scan.sh /path/to/repo`

### Layer 3: CI/CD

GitHub Action wrapper around Layer 2 scripts. Enables integration into CI/CD pipelines with standard GitHub Actions syntax, step summaries, and output variables.

**Consumption**:
```yaml
# Pin to a release tag (for example @v0.0.1) for reproducibility.
- uses: PSDN-AI/nexus-skills/skills/repo-public-readiness@main
  with:
    repo_path: "."
```

## Cross-Repo Integration: nexus-skills + nexus-agents

### Relationship

| Repo | Role |
|------|------|
| `nexus-skills` | Atomic knowledge modules — one Skill solves one problem |
| `nexus-agents` | Composite orchestrators — one Agent composes multiple Skills into a workflow |

### How Agents Reference Skills

Agents declare Skill dependencies in `config.yaml`. The reference is a pointer, not a code import:

```yaml
# nexus-agents/agents/repo-guardian/config.yaml
skills:
  - name: repo-public-readiness
    version: "1.0.0"
    source: https://github.com/PSDN-AI/nexus-skills
    path: skills/repo-public-readiness
```

### Resolution at Runtime

An AI Agent consuming an Agent definition:

1. Reads `AGENT.md` to understand the orchestration workflow.
2. Reads `config.yaml` to discover Skill dependencies.
3. For each Skill, fetches `SKILL.md` from the source (GitHub raw URL or local clone).
4. Follows the orchestration logic in `AGENT.md`, executing each Skill in sequence.
5. If scripts are available and preferred, runs them via Layer 2 instead of following SKILL.md manually.

No package manager, no git submodules. Git + URL is the distribution mechanism.

## Versioning

- **nexus-skills** uses git tags (`v0.0.1`, `v0.1.0`, `v1.0.0`, etc.) on the repository.
- **Agents** pin Skill versions in `config.yaml` to ensure reproducibility.
- **GitHub Actions** consumers can start with `@main`, then pin to a release tag (`@v0.0.1`, `@v1.0.0`) for reproducibility.

## Discovery

`catalog.yaml` in nexus-skills serves as the machine-readable registry:

```yaml
skills:
  - name: repo-public-readiness
    version: 1.0.0
    description: "Scan a repo for secrets, quality issues, missing docs, and compliance problems"
    path: skills/repo-public-readiness
```

AI Agents or tooling can fetch `catalog.yaml` to discover available Skills, then load individual `SKILL.md` files as needed.
