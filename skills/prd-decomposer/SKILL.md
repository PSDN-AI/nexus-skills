---
name: prd-decomposer
description: "Decomposes a Product Requirements Document (PRD) into domain-specific specs for AI Agent consumption. Use when given a PRD, product spec, or technical design document that needs to be broken down into frontend, backend, infra, devops, security, or other domain folders. Each output folder contains a self-contained spec, boundary conditions, and agent configuration. Supports Markdown and plain text PRDs. Do NOT use for code review, repo scanning, or non-document tasks."
license: MIT
compatibility: "Requires bash 4.0+, grep, sed, awk, find, sort, wc. Optional: yq (YAML processing), jq (JSON output)."
metadata:
  author: PSDN-AI
  version: "0.1.0"
---

# PRD Decomposer

> Transform a monolithic Product Requirements Document into domain-scoped work units that AI Agents can independently implement, each with its own spec, boundary conditions, and configuration.

## Table of Contents

- [When Should You Use This?](#when-should-you-use-this)
- [How This Skill Can Be Used](#how-this-skill-can-be-used)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Decomposition Workflow](#decomposition-workflow)
- [Domain Taxonomy](#domain-taxonomy)
- [Output Structure](#output-structure)
- [Constitutional Constraints](#constitutional-constraints)
- [Validation](#validation)
- [Common Pitfalls](#common-pitfalls)

## When Should You Use This?

- You have a PRD, product spec, or technical design document that needs to be broken into actionable work units.
- You want to feed domain-specific specs to downstream AI Agents (one per domain).
- You need cross-domain contracts extracted (API interfaces, data schemas, infra requirements).
- You want a structured folder that an orchestrator can distribute to specialized agents.

## How This Skill Can Be Used

| Model | How it works | When to use |
|-------|-------------|-------------|
| **A — Script Execution** | Run `decompose.sh` with a PRD file to generate structured output | You have bash and want deterministic, automated decomposition |
| **B — Knowledge-Driven** | An LLM reads this SKILL.md and performs decomposition using its own tools | No bash available, or the LLM needs flexibility to handle ambiguous PRDs |
| **C — Hybrid** | An LLM runs the scripts AND uses this spec to interpret, extend, or refine results | Best coverage — combines automation with LLM judgment for ambiguity resolution |

## Prerequisites

**Required** (built-in on macOS/Linux):
- `bash` (4.0+), `grep`, `sed`, `awk`, `find`, `sort`, `wc`, `date`

**Optional** (enhanced output when available):
- `yq` — structured YAML generation (falls back to echo-based YAML without it)
- `jq` — required for `--output-format json`

## Quick Start

```bash
# Basic usage — generates output in ./prd-output/
./skills/prd-decomposer/scripts/decompose.sh /path/to/prd.md

# Specify output directory
./skills/prd-decomposer/scripts/decompose.sh /path/to/prd.md --output /path/to/output

# Dry run — parse and classify only, print summary
./skills/prd-decomposer/scripts/decompose.sh /path/to/prd.md --dry-run

# Custom domain taxonomy
./skills/prd-decomposer/scripts/decompose.sh /path/to/prd.md --taxonomy /path/to/custom.yaml

# Verbose mode
./skills/prd-decomposer/scripts/decompose.sh /path/to/prd.md --verbose
```

## Decomposition Workflow

Follow these six phases in order:

```
Progress:
- [ ] Phase 1: PARSE    — Read the PRD, identify sections, extract structure
- [ ] Phase 2: CLASSIFY — Map sections to domains using taxonomy
- [ ] Phase 3: EXTRACT  — Pull content into domain-specific specs
- [ ] Phase 4: CONNECT  — Identify cross-domain dependencies, generate contracts
- [ ] Phase 5: GENERATE — Write output files into structured folder
- [ ] Phase 6: VALIDATE — Self-check completeness and consistency
```

### Phase 1: PARSE

Read the PRD and identify its structure:

1. Detect headings (H1–H4 in Markdown: `^#{1,4}\s`). In plain text, detect numbered sections (`^[0-9]+\.`).
2. Identify section boundaries: a section runs from its heading to the next heading of same or higher level.
3. Extract content within each section, preserving code blocks, tables, bullet lists, and Mermaid diagrams verbatim.
4. Extract metadata from the document header if present: title (first H1), author, date, version.

### Phase 2: CLASSIFY

For each section, score it against the domain taxonomy:

1. Tokenize the section content (split on whitespace and punctuation).
2. For each domain in the taxonomy, count keyword matches (case-insensitive, word-boundary matching).
3. Normalize scores by section length to prevent bias toward longer sections.
4. Assign the section to the highest-scoring domain.
5. If a section scores above 60% of its top score in a second domain, flag it as having a cross-domain reference.
6. If no domain scores above 0, assign to `uncategorized`.

See [references/domain-taxonomy.yaml](references/domain-taxonomy.yaml) for the default domain definitions and keywords.

### Phase 3: EXTRACT

For each identified domain, collect all assigned sections:

1. Group sections by their classified domain.
2. Preserve the original section headings and content exactly as written.
3. Mark each piece of content as `[EXTRACTED]` (from PRD) vs `[GENERATED]` (synthesized by decomposer).
4. Extract acceptance criteria from "must", "shall", "should", "may" statements.
5. Extract constraints from "constraint", "limitation", "non-functional" sections.

### Phase 4: CONNECT

Identify cross-domain dependencies and contracts:

1. For each domain pair, check if sections reference each other (e.g., "Frontend calls Backend API").
2. Extract API contracts: endpoints, methods, paths mentioned in PRD.
3. Extract data contracts: schemas, database references shared between domains.
4. Extract infra requirements: runtime dependencies from code domains to infrastructure.
5. Build a dependency graph showing domain relationships.

### Phase 5: GENERATE

Write output files. See [Output Structure](#output-structure) for the exact file format.

### Phase 6: VALIDATE

Self-check the decomposition:

1. Verify every PRD section appears in at least one domain spec or in `uncategorized/`.
2. Verify no content was silently dropped.
3. Check that cross-domain references have corresponding contracts.
4. Calculate coverage percentage: classified sections / total sections.
5. Flag any sections with vague requirements (no measurable criteria).

## Domain Taxonomy

The default taxonomy defines seven domains. See [references/domain-taxonomy.yaml](references/domain-taxonomy.yaml) for the full keyword list.

| Domain | Aliases | Focus |
|--------|---------|-------|
| `frontend` | fe, client, ui, web | UI components, pages, routing, state management |
| `backend` | be, server, api | APIs, services, databases, auth, queues |
| `infra` | infrastructure, cloud, platform | Cloud providers, Kubernetes, IaC, networking |
| `devops` | cicd, pipeline, deployment | CI/CD, monitoring, alerting, deployment strategies |
| `security` | sec, compliance, audit | Encryption, auth hardening, compliance, WAF |
| `data` | ml, ai, analytics, data-eng | Data pipelines, ML models, analytics, warehousing |
| `shared` | common, cross-cutting | Shared types, API schemas, protobuf, error codes |

Users can override the taxonomy with `--taxonomy /path/to/custom.yaml`.

## Output Structure

See [references/output-schema.md](references/output-schema.md) for the detailed output format specification.

The decomposer generates this folder structure:

```
prd-output/
├── meta.yaml                      # Project metadata and decomposition summary
├── contracts/
│   ├── api-contracts.yaml         # REST/GraphQL endpoints shared between domains
│   ├── data-contracts.yaml        # Data schemas shared between domains
│   ├── infra-requirements.yaml    # Runtime requirements for infrastructure
│   └── dependency-graph.md        # Mermaid diagram of domain dependencies
├── {domain}/                      # One folder per identified domain
│   ├── spec.md                    # Decomposed requirements spec
│   ├── boundary.yaml              # Acceptance criteria and constraints
│   └── config.yaml                # Agent configuration (human fills target_repo)
└── uncategorized/                 # Sections that couldn't be classified
    └── spec.md
```

## Constitutional Constraints

These rules are non-negotiable:

1. **Never invent requirements** not present in the PRD.
2. **Never remove or merge sections** without explanation in the output.
3. **Always preserve original PRD text** in extracted specs — quote, don't paraphrase.
4. **Always mark content origin**: `[EXTRACTED]` for PRD content, `[GENERATED]` for synthesized content.
5. **Every PRD section must appear** in at least one domain spec or in `uncategorized/`.
6. **Idempotent output**: running the decomposer twice on the same PRD produces the same result.

## Validation

After decomposition:

- `meta.yaml` contains `coverage_percent` — should be 100% for a well-structured PRD.
- Every domain folder contains `spec.md`, `boundary.yaml`, and `config.yaml`.
- `contracts/dependency-graph.md` contains a Mermaid diagram if cross-domain dependencies exist.
- Running the decomposer twice on the same PRD produces identical output (deterministic).
- For Model B: the LLM should follow all six phases and produce the same folder structure. Phases that cannot be fully automated should be noted in `meta.yaml`.

## Common Pitfalls

- **PRD with no clear sections**: If the PRD lacks headings, the parser treats the entire document as one section assigned to `uncategorized`. Add headings or use `--verbose` to see parsing details.
- **Overlapping domains**: Some sections naturally span multiple domains (e.g., "JWT authentication" touches both backend and security). The decomposer assigns to the primary domain and adds a cross-reference — it does not duplicate content.
- **Mermaid diagrams**: The script extracts Mermaid blocks but cannot fully parse them. For Model B/C, the LLM should interpret Mermaid diagrams to validate classification.
- **Custom taxonomy missing keywords**: If using a custom taxonomy, ensure keywords are comprehensive. Low keyword coverage leads to many `uncategorized` sections.
- **Large PRDs**: PRDs over 50 sections may produce verbose output. Use `--dry-run` first to review classification before generating files.
- **Non-English PRDs**: The default taxonomy uses English keywords. For other languages, provide a custom taxonomy with translated keywords.
