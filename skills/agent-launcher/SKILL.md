---
name: agent-launcher
description: "Executes a tasks.yaml task graph (output of spec-plan) as a controlled implementation run: launches isolated sub-agents per task, enforces dependency ordering and file-scope boundaries, merges successful results into an integration branch, and emits a machine-readable run report. Use when you have a planned task graph and need to orchestrate parallel agent execution with safety guardrails. Do NOT use for planning tasks (use spec-plan) or decomposing PRDs (use prd-decompose)."
license: MIT
compatibility: "Requires bash 4.0+, git 2.20+, grep, sed, awk, find, sort, comm, mktemp."
metadata:
  author: PSDN-AI
  version: "0.1.0"
  category: Product Engineering
  tags:
    - orchestration
    - multi-agent
    - execution
    - task-graph
    - git-workflow
---

# Agent Launcher

> Execute a task graph as a controlled implementation run with isolated sub-agents, dependency enforcement, file-scope guardrails, and a machine-readable run report.

## Table of Contents

- [When Should You Use This?](#when-should-you-use-this)
- [How This Skill Can Be Used](#how-this-skill-can-be-used)
- [Pipeline Context](#pipeline-context)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Execution Workflow](#execution-workflow)
- [Constitutional Constraints](#constitutional-constraints)
- [Output Format](#output-format)
- [Validation](#validation)
- [Common Pitfalls](#common-pitfalls)

## When Should You Use This?

- You have a `tasks.yaml` from `spec-plan` and want to execute it automatically.
- You need dependency-ordered, parallel-safe agent execution with isolation.
- You want file-scope enforcement to prevent merge conflicts.
- You need a structured run report for human review or downstream automation.

## How This Skill Can Be Used

| Model | How it works | When to use |
|-------|-------------|-------------|
| **A -- Script Execution** | Run `launch.sh` to orchestrate task execution and produce a run report | Primary mode -- deterministic orchestration with guardrails |
| **B -- Knowledge-Driven** | An LLM reads this SKILL.md and manually orchestrates task execution | No bash available, or the LLM needs to handle edge cases scripts don't cover |
| **C -- Hybrid** | An LLM uses `launch.sh` for scheduling and workspace setup, then invokes sub-agents manually per task | Best coverage -- script handles deterministic parts, LLM handles agent invocation |

**This skill is Layer 2 primary**: scripts handle queueing, workspace isolation, merge sequencing, and status tracking. The SKILL.md guides orchestration policy, escalation, and judgment calls.

## Pipeline Context

```
+-------------------+     +-------------------+     +-------------------+
| prd-decompose     | --> | spec-plan         | --> | agent-launcher    |
| Skill             |     | Skill             |     | Skill             |
|                   |     |                   |     |                   |
| PRD -> Domains    |     | Domain -> Tasks   |     | Tasks -> Code/PR  |
+-------------------+     +-------------------+     +-------------------+
```

**Upstream**: `spec-plan` produces `tasks.yaml` with dependency ordering and file-scope declarations.
**Output**: Validated code on an integration branch, plus a structured `run-report.yaml`.

## Prerequisites

**Required**:
- `bash` (4.0+), `git` (2.20+), `grep`, `sed`, `awk`, `find`, `sort`, `comm`, `mktemp`

**Input files** (from `spec-plan`):
- `tasks.yaml` -- task graph with dependencies, file-scope, and execution plan
- `config.yaml` -- target_repo, target_branch, agent_model, max_iterations

**Runtime requirement**:
- A git repository checkout for the target project (passed via `--repo`)
- A clean working tree on the target repository
- An execution backend:
  - Set `AGENT_LAUNCHER_EXECUTOR` to a shell command that performs the task and commits changes
  - Or set `AGENT_LAUNCHER_SIMULATE=true` for fixture/tests only

## Quick Start

```bash
# Preview execution plan without making changes
./skills/agent-launcher/scripts/launch.sh /path/to/prd-output/frontend/ \
  --repo /path/to/target-repo/ --dry-run

# Execute all tasks
AGENT_LAUNCHER_EXECUTOR='codex exec --prompt-file "$AGENT_LAUNCHER_PROMPT_FILE"' \
  ./skills/agent-launcher/scripts/launch.sh /path/to/prd-output/frontend/ \
  --repo /path/to/target-repo/

# Limit concurrency
AGENT_LAUNCHER_EXECUTOR='codex exec --prompt-file "$AGENT_LAUNCHER_PROMPT_FILE"' \
  ./skills/agent-launcher/scripts/launch.sh /path/to/prd-output/frontend/ \
  --repo /path/to/target-repo/ --max-parallel 2

# Resume an interrupted run
AGENT_LAUNCHER_EXECUTOR='codex exec --prompt-file "$AGENT_LAUNCHER_PROMPT_FILE"' \
  ./skills/agent-launcher/scripts/launch.sh /path/to/prd-output/frontend/ \
  --repo /path/to/target-repo/ --resume run-20260303-001

# Simulation mode for local fixture tests only
AGENT_LAUNCHER_SIMULATE=true \
  ./skills/agent-launcher/scripts/launch.sh /path/to/prd-output/frontend/ \
  --repo /path/to/target-repo/
```

Exit codes: `0` success | `1` missing input | `2` invalid tasks.yaml or repo state | `3` workspace failure | `4` task execution failure | `5` merge failure

## Execution Workflow

Follow these eight phases in order:

```
Progress:
- [ ] Phase 1: LOAD      -- Read tasks.yaml, config.yaml, repo state
- [ ] Phase 2: VALIDATE  -- Confirm DAG validity and repo cleanliness
- [ ] Phase 3: SCHEDULE  -- Determine ready tasks from depends_on + execution_plan
- [ ] Phase 4: PREPARE   -- Create integration branch and task workspaces
- [ ] Phase 5: EXECUTE   -- Launch sub-agent per ready task
- [ ] Phase 6: VERIFY    -- Confirm only declared files changed
- [ ] Phase 7: MERGE     -- Merge successful tasks into integration branch
- [ ] Phase 8: REPORT    -- Emit run-report.yaml and human summary
```

### Phase 1: LOAD

1. Read `tasks.yaml` and parse task graph, execution plan, and validation summary.
2. Read `config.yaml` for target_repo, target_branch, agent_model, max_iterations.
3. If `--resume` is set, load prior `run-report.yaml`, verify the `execution_id` matches, and restore successful task statuses.
4. Count total tasks and phases for scheduling.

### Phase 2: VALIDATE

1. Verify `tasks.yaml` has required structure (tasks, execution_plan, validation).
2. Verify the target repository exists and is a valid git repo.
3. Verify the base branch exists in the repository.
4. Check for uncommitted changes in the working tree.
5. Verify `AGENT_LAUNCHER_EXECUTOR` is set unless simulation mode is explicitly enabled.

### Phase 3: SCHEDULE

1. Build a ready queue from the execution plan phases.
2. For each phase, identify tasks whose dependencies are all satisfied.
3. Split parallel phases into conflict-free batches so no batch exceeds `--max-parallel` and no two tasks in a batch overlap in `files_touched`.
4. Mark tasks as `blocked` if any dependency has failed or become blocked.

### Phase 4: PREPARE

1. Create or reuse the integration branch: `agent-launcher/{domain}/{execution-id}` from the base branch.
2. Reset each per-task branch: `agent/{task-id-lower}` to the integration branch tip before execution.
3. Create a dedicated git worktree per active task branch.

See [references/execution-contract.md](references/execution-contract.md) for workspace isolation rules.

### Phase 5: EXECUTE

For each ready task:

1. Check dependency gates (all `depends_on` must be `succeeded`).
2. Write `.agent-launcher/{task-id}.prompt.md` inside the task worktree.
3. Invoke the configured executor inside the task worktree with the task's `prompt_context`.
4. The executor commits changes to the task branch.

See [references/prompt-template.md](references/prompt-template.md) for the standard launch prompt format.

### Phase 6: VERIFY

After each task completes:

1. Compare files actually changed on the task branch against declared `files_touched`.
2. If the task modified undeclared files, mark it as `failed` (scope violation).
3. If verification passes, mark the task as `succeeded`.

### Phase 7: MERGE

1. Merge successful tasks into the integration branch in execution plan order.
2. Use `--no-ff` merges to preserve task provenance.
3. If a merge conflict occurs, abort, mark the task as `failed`, and continue processing later tasks.

See [references/execution-contract.md](references/execution-contract.md) for merge protocol details.

### Phase 8: REPORT

1. Write `run-report.yaml` with per-task status, commit SHAs, and summary stats.
2. Print a human-readable summary showing succeeded, failed, and blocked tasks.
3. Indicate whether the integration branch is PR-ready (all tasks succeeded).
4. Exit with `4` if any task failed or was blocked, or `5` if any merge failed.

See [references/example-run-report.yaml](references/example-run-report.yaml) for a worked example.

## Constitutional Constraints

These rules are non-negotiable:

1. **Never launch a task until all `depends_on` tasks have status `succeeded`.**
2. **Never run two tasks concurrently if their `files_touched` overlap.**
3. **Never merge changes outside a task's declared `files_touched`** without explicit human approval.
4. **Never merge a task that failed validation**, exceeded retry limits, or produced ambiguous state.
5. **Always execute from a dedicated integration branch**, never directly on the target base branch.
6. **Always execute task work in isolated worktrees**, not in the repository's primary checkout.
7. **Every task run must leave a structured status trail** in `run-report.yaml`.
8. **Never run without an explicit executor contract** unless simulation mode is intentionally enabled.
9. **Stop retrying when policy is exhausted**; surface a precise handoff instead of looping.
10. **Respect `agent_model` and `max_iterations`** from `config.yaml`.

## Output Format

### run-report.yaml

See [references/example-run-report.yaml](references/example-run-report.yaml) for the complete schema.

Key sections:
- **Header**: execution_id, domain, target_repo, branches, timestamps
- **Tasks**: per-task status, branch, commit_sha, retries, failure reason
- **Summary**: counts by status, merge count, PR readiness

### Integration Branch

All successfully merged task work lives on `agent-launcher/{domain}/{execution-id}`. This branch is suitable for opening a PR against the base branch.

### Failure Handling

See [references/failure-policy.md](references/failure-policy.md) for retry, blocking, resume, and escalation rules.

## Validation

After a run:

- `run-report.yaml` contains accurate per-task status and summary counts.
- Succeeded tasks have commit SHAs that match the integration branch history.
- Failed tasks have a `reason` field explaining the failure.
- Blocked tasks trace back to a specific dependency constraint recorded in the report.
- The integration branch contains only changes from succeeded tasks.

## Common Pitfalls

- **Dirty working tree**: The launcher requires a clean git state. Commit or stash changes before running.
- **Missing executor**: Production runs fail closed unless `AGENT_LAUNCHER_EXECUTOR` is set. Simulation mode is for tests only.
- **Base branch mismatch**: If the target_branch in config.yaml doesn't match the repo's current state, the integration branch starts from the wrong point.
- **File scope false negatives**: If `files_touched` in tasks.yaml is incomplete, the guardrails will flag legitimate changes as scope violations. Fix the task plan first.
- **Merge order sensitivity**: Tasks must merge in topological order. Merging a downstream task before its upstream dependency causes conflicts.
- **Resume with modified tasks.yaml**: If you change tasks.yaml between runs, resume may restore stale successes from the prior `execution_id`. Start a fresh run instead of reusing the old ID.
- **Max iterations too low**: Complex tasks may need more iterations. Check config.yaml if tasks consistently fail at the retry limit.
