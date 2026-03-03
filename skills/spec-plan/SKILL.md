---
name: spec-plan
description: "Converts a decomposed domain folder (output of prd-decompose) into tasks.yaml — an executable task graph with dependency ordering, parallelization strategy, and file-scope isolation. Use when you have a domain spec folder containing spec.md and boundary.yaml and need to plan concrete implementation tasks for AI agents. Do NOT use for PRD decomposition (use prd-decompose instead) or for executing tasks (use a future agent-launcher skill)."
license: MIT
compatibility: "Requires bash 4.0+, grep, sed, awk, find, sort, comm. Optional: yq (YAML validation)."
metadata:
  author: PSDN-AI
  version: "0.1.0"
  category: Product Engineering
  tags:
    - planning
    - task-graph
    - decomposition
    - multi-agent
    - dependency-ordering
---

# Spec Plan

> Turn a domain specification into an executable task graph that AI agents can independently implement, with dependency ordering, parallelization safety, and acceptance criteria traceability.

## Table of Contents

- [When Should You Use This?](#when-should-you-use-this)
- [How This Skill Can Be Used](#how-this-skill-can-be-used)
- [Pipeline Context](#pipeline-context)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Planning Workflow](#planning-workflow)
- [Constitutional Constraints](#constitutional-constraints)
- [Domain Heuristics Summary](#domain-heuristics-summary)
- [Output Format](#output-format)
- [Validation](#validation)
- [Common Pitfalls](#common-pitfalls)

## When Should You Use This?

- You have a domain folder from `prd-decompose` with `spec.md` and `boundary.yaml`.
- You need to break a spec into discrete, parallelizable tasks for AI agents.
- You want dependency ordering that prevents merge conflicts in parallel execution.
- You need every acceptance criterion mapped to at least one implementation task.

## How This Skill Can Be Used

| Model | How it works | When to use |
|-------|-------------|-------------|
| **A — Script Execution** | Run `plan.sh --validate-only` to validate an existing `tasks.yaml` | You already have a task graph and want to verify it |
| **B — Knowledge-Driven** | An LLM reads this SKILL.md and generates `tasks.yaml` following the 7-phase workflow | Primary mode — planning requires understanding component relationships |
| **C — Hybrid** | An LLM generates `tasks.yaml`, then runs `plan.sh --validate-only` to verify | Best coverage — combines AI judgment with automated validation |

**This skill is Layer 1 primary**: the AI performs the planning; scripts only validate output. Deciding that "shared UI components must precede pages" requires reading and understanding component relationships — a task for the AI, not a bash script.

## Pipeline Context

```
+-------------------+     +-------------------+     +-------------------+
| prd-decompose     |     | spec-plan         |     | agent-launcher    |
| (Skill)           | --> | (Skill)           | --> | (Future Skill)    |
|                   |     |                   |     |                   |
| PRD -> Domains    |     | Domain -> Tasks   |     | Task -> Code -> PR|
+-------------------+     +-------------------+     +-------------------+
```

**Upstream**: `prd-decompose` produces the domain folder this skill consumes.
**Downstream**: `agent-launcher` (future) reads `tasks.yaml` and spawns sub-agents per task.

## Prerequisites

**Required** (built-in on macOS/Linux):
- `bash` (4.0+), `grep`, `sed`, `awk`, `find`, `sort`, `comm`

**Input files** (from `prd-decompose`):
- `spec.md` — domain requirements with `[EXTRACTED]` and `[GENERATED]` markers
- `boundary.yaml` — acceptance criteria (P0/P1/P2), constraints, test hints
- `config.yaml` — agent configuration (optional, not consumed by planner)

**Optional**:
- `contracts/` directory with `api-contracts.yaml`, `data-contracts.yaml` for cross-domain context
- `yq` — for structured YAML validation

## Quick Start

```bash
# Validate an existing tasks.yaml
./skills/spec-plan/scripts/plan.sh /path/to/prd-output/frontend/ --validate-only

# Run planner with verbose output
./skills/spec-plan/scripts/plan.sh /path/to/prd-output/frontend/ --verbose

# Include cross-domain contracts
./skills/spec-plan/scripts/plan.sh /path/to/prd-output/frontend/ \
  --contracts /path/to/prd-output/contracts/
```

Exit codes: `0` success | `1` missing input | `2` YAML structure error | `3` files_touched conflict | `4` AC coverage gap | `5` internal error

## Planning Workflow

Follow these seven phases in order. This is the core of the skill — the AI reads the spec and produces `tasks.yaml`.

```
Progress:
- [ ] Phase 1: ANALYZE    -- Read all input files, understand the domain
- [ ] Phase 2: DECOMPOSE  -- Identify discrete implementable tasks
- [ ] Phase 3: SCOPE      -- Define files_touched and prompt_context per task
- [ ] Phase 4: ORDER      -- Build dependency DAG and execution phases
- [ ] Phase 5: MAP        -- Assign acceptance criteria to tasks
- [ ] Phase 6: VALIDATE   -- Run validation scripts, fix issues
- [ ] Phase 7: OUTPUT     -- Write tasks.yaml
```

### Phase 1: ANALYZE

Read and understand the domain context:

1. Read `spec.md` — identify all requirements, paying attention to `[EXTRACTED]` vs `[GENERATED]` markers.
2. Read `boundary.yaml` — note all acceptance criteria and their priorities (P0, P1, P2).
3. Read `config.yaml` — note target repo, agent model, iteration limits.
4. If `--contracts` provided, read relevant contract files for cross-domain API/data dependencies.
5. Identify the domain type (frontend, backend, infra, devops, security) for heuristic selection.

### Phase 2: DECOMPOSE

Break the spec into discrete work units:

1. Identify natural task boundaries — each task should be completable by one agent in one session.
2. Target 1-3 files and 100-500 LOC per task. Split larger scopes.
3. Apply domain heuristics (see [Domain Heuristics Summary](#domain-heuristics-summary) and [references/domain-heuristics.md](references/domain-heuristics.md)).
4. Identify shared code (components, utilities, middleware) that multiple features depend on — these become early-phase tasks.
5. Mark AI-generated infrastructure tasks (linting, CI setup) as `[GENERATED]` with P2 priority.

### Phase 3: SCOPE

For each task, define its boundaries:

1. **files_touched**: List every file the task will create or modify. Be conservative — unlisted files that get modified cause merge conflicts in parallel execution.
2. **prompt_context**: Write a self-contained description. The implementing agent reads ONLY this field, not the full spec. Include:
   - What to build (requirements)
   - How to build it (technologies, patterns)
   - Constraints and acceptance criteria
   - API endpoints or data schemas if relevant
3. Keep prompt_context under 500 words per task.

### Phase 4: ORDER

Build the dependency graph and execution phases:

1. For each task, identify which other tasks must complete first (`depends_on`).
2. Verify the dependency graph is a DAG — no circular dependencies.
3. Group tasks into sequential phases:
   - Phase 1: tasks with no dependencies (root tasks)
   - Phase N: tasks whose dependencies are all in earlier phases
4. Within each phase, check if tasks can parallelize:
   - `parallel: true` only if all tasks have zero overlap in `files_touched`
   - `parallel: false` otherwise (or for single-task phases)
5. Write a `reason` for each phase explaining the ordering decision.

### Phase 5: MAP

Connect acceptance criteria to tasks:

1. For each AC in `boundary.yaml`, identify which task(s) satisfy it.
2. Add the AC ID to the task's `acceptance_criteria` list.
3. Every P0 AC must be mapped to at least one task.
4. P1 and P2 ACs should be mapped where possible.
5. List any unmapped ACs in `validation.unmapped_criteria` with an explanation.

### Phase 6: VALIDATE

Run automated checks (Model C), or verify manually (Model B):

```bash
# Validate structure, conflicts, and coverage
./skills/spec-plan/scripts/plan.sh /path/to/domain/ --validate-only
```

The validator checks:
- YAML structure: required keys, valid field types, task ID format
- DAG validity: no circular dependencies, all dependency targets exist
- File conflicts: no `files_touched` overlap within parallel phases
- AC coverage: all P0 acceptance criteria mapped to tasks

Fix any issues before proceeding to output.

### Phase 7: OUTPUT

Write `tasks.yaml` to the domain directory. See [Output Format](#output-format) for the schema.

Assign task IDs using the domain prefix convention:
- Frontend: FE-001, FE-002, ...
- Backend: BE-001, BE-002, ...
- Infrastructure: INFRA-001, INFRA-002, ...
- DevOps: DEVOPS-001, ...
- Security: SEC-001, ...

## Constitutional Constraints

These rules are non-negotiable:

1. **Every task must be completable in isolation** — no cross-task context needed. The `prompt_context` is the agent's only input.
2. **Never create circular dependencies** — the task graph must be a DAG.
3. **`files_touched` must be conservative** — false negatives cause merge conflicts. When in doubt, include the file.
4. **Every acceptance criterion must map to at least one task** — unmapped ACs are surfaced in `validation.unmapped_criteria`.
5. **`prompt_context` must be fully self-contained** — do not reference other tasks, do not assume context from other phases.
6. **Never invent requirements** — all tasks must trace back to `spec.md` content. AI-generated infrastructure tasks (e.g., "set up linting") are marked `[GENERATED]` with priority P2.

## Domain Heuristics Summary

See [references/domain-heuristics.md](references/domain-heuristics.md) for detailed guidance.

| Domain | Phase 1 | Phase 2 | Parallelization Pattern |
|--------|---------|---------|------------------------|
| Frontend | Scaffolding | Shared UI components | Pages without shared state |
| Backend | DB schema/migrations | Auth middleware, utilities | Independent API resources |
| Infra | Terraform backend | Networking (VPC/subnets) | Compute + storage modules |
| DevOps | Dockerfile + build config | CI pipeline | Env-specific configs |
| Security | Auth setup | Secret management | Hardening tasks on different files |

## Output Format

See [references/output-schema.md](references/output-schema.md) for the complete field specification.

See [references/example-tasks.yaml](references/example-tasks.yaml) for a complete worked example.

The output is a single `tasks.yaml` file with four sections:

1. **Header**: version, domain, generated_at, generated_from
2. **Tasks**: list of task objects with id, name, depends_on, estimated_complexity, files_touched, acceptance_criteria, prompt_context
3. **Execution plan**: ordered phases with parallelization flags
4. **Validation**: summary statistics for downstream tools

Key design points:
- **`files_touched`** is the parallelization safety mechanism — two tasks in the same phase must have zero overlap.
- **`prompt_context`** is a curated spec excerpt per task, not the full spec.
- **Task IDs use domain prefix** (FE-001, BE-001, INFRA-001) to prevent collisions across domains.

## Validation

After generating `tasks.yaml`, validate it:

```bash
./skills/spec-plan/scripts/plan.sh /path/to/domain/ --validate-only
```

Three checks run:
1. **Structure**: Required fields, valid types, task ID format, DAG validity
2. **File conflicts**: No `files_touched` overlap in parallel phases
3. **AC coverage**: All P0 acceptance criteria mapped to at least one task

For Model B (no script execution), verify manually:
- Every task has all required fields (id, name, depends_on, estimated_complexity, files_touched, acceptance_criteria, prompt_context)
- Task IDs follow PREFIX-NNN format
- No circular dependencies in depends_on chains
- Parallel phases have zero file overlap
- All P0 ACs from boundary.yaml appear in task acceptance_criteria lists

## Common Pitfalls

- **Too-large tasks**: If a task touches more than 8 files or exceeds 500 LOC, split it. Large tasks reduce parallelization opportunities and increase agent failure rates.
- **Missing shared dependencies**: Forgetting that multiple pages import from the same barrel file or utility module. These shared files must be assigned to one task, with that task as a dependency for consumers.
- **Optimistic files_touched**: Listing only new files, forgetting that the task also modifies existing config files, route definitions, or type exports.
- **Cross-task context leaks**: Writing prompt_context that says "use the component from FE-002". The agent has no access to FE-002's output. Instead, describe the component interface directly in the prompt_context.
- **Unmapped acceptance criteria**: Every AC should trace to a task. If an AC cannot be mapped (e.g., it's too vague), list it in `unmapped_criteria` and note why.
- **Circular dependencies**: A depends on B depends on C depends on A. The validator catches this, but it's easier to prevent by always thinking in terms of "what must exist before this task can start?"
- **Parallel conflicts**: Two tasks in the same phase both modifying `package.json` or `index.ts`. These barrel/config files are common conflict sources — assign them to one task.
