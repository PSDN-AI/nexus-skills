# Execution Contract

Detailed orchestration rules, state model, and scheduling logic for agent-launcher.

## Table of Contents

- [Task State Model](#task-state-model)
- [Scheduling Rules](#scheduling-rules)
- [Workspace Isolation](#workspace-isolation)
- [Executor Contract](#executor-contract)
- [Merge Protocol](#merge-protocol)
- [Concurrency Control](#concurrency-control)

## Task State Model

Each task progresses through these states:

```
pending -> running -> succeeded -> (merged)
                  \-> failed    -> (dependents blocked)
       \-> blocked (dependency failed)
```

| State | Meaning |
|-------|---------|
| `pending` | Not yet started, waiting for turn |
| `running` | Currently being executed by a sub-agent |
| `succeeded` | Execution completed, file scope verified |
| `failed` | Execution failed or scope violation, retries exhausted |
| `blocked` | Upstream dependency failed, will not execute |

State transitions are recorded in the status directory and persisted to `run-report.yaml`.

## Scheduling Rules

1. **Phase ordering is strict**: tasks in phase N never start before all phase N-1 tasks reach a terminal state (succeeded, failed, blocked, skipped).
2. **Dependency gates are hard**: a task with `depends_on: [A, B]` starts only when both A and B have status `succeeded`.
3. **Failure cascades immediately**: when a task fails, all transitive dependents are marked `blocked` without waiting for sibling tasks.
4. **Resume is exact-match only**: `--resume <execution-id>` is accepted only when `run-report.yaml` exists and its `execution_id` matches exactly.
5. **Parallel tasks within a phase** may run concurrently only if `parallel: true` in the execution plan and their `files_touched` have zero overlap.
6. **Max concurrency** is capped by `--max-parallel` (default 3).

## Workspace Isolation

Every task executes on its own git branch and worktree:

```
main (base branch in primary checkout)
 |
 +-- agent-launcher/{domain}/{exec-id}     (integration branch)
      |
      +-- agent/{task-id-lower}            (task branch, per task)
           |
           +-- /tmp/.../worktree           (ephemeral task worktree)
```

- The **integration branch** is created from the base branch at launch time and reused on resume. Agents never write to the primary checkout.
- Each **task branch** is reset from the current integration branch tip before execution. The executor commits only to its task branch.
- Each active task runs inside a dedicated **git worktree** so concurrent tasks do not mutate the same checkout.
- After verification, task branches are merged into the integration branch in topological order.

## Executor Contract

The launcher fails closed unless one of these is true:

- `AGENT_LAUNCHER_EXECUTOR` is set to a shell command
- `AGENT_LAUNCHER_SIMULATE=true` is set for fixture/tests

When `AGENT_LAUNCHER_EXECUTOR` is used, the command runs inside the task worktree with these exported variables:

- `AGENT_LAUNCHER_REPO_DIR`
- `AGENT_LAUNCHER_TASK_ID`
- `AGENT_LAUNCHER_TASK_NAME`
- `AGENT_LAUNCHER_PROMPT_FILE`
- `AGENT_LAUNCHER_FILES_TOUCHED`
- `AGENT_LAUNCHER_MAX_ITERATIONS`

The executor is responsible for:

1. Reading the generated prompt file.
2. Modifying only files declared in `files_touched`.
3. Creating at least one commit on the task branch.

## Merge Protocol

1. Tasks merge in execution plan order (phase 1 first, then phase 2, etc.).
2. Within a phase, tasks merge in task ID order (deterministic).
3. Each merge uses `--no-ff` to preserve task provenance in the git history.
4. If a task branch is already reachable from the integration branch (resume case), the merge is skipped as a no-op.
5. If a merge produces a conflict, the merge is aborted and the task is marked `failed`.
6. Failed merges do not affect the integration branch state (it remains at the last successful merge).

## Concurrency Control

- **Low complexity** tasks: eligible for parallel execution when the execution plan marks the phase parallel.
- **High complexity** tasks: still require explicit `parallel: true` in the execution plan and zero file overlap.
- **files_touched overlap**: always blocks parallel execution, regardless of complexity or plan flags.
- The scheduler batches phase work so it never launches more than `--max-parallel` tasks simultaneously.
