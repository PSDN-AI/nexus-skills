# Execution Contract

Detailed orchestration rules, state model, and scheduling logic for agent-launcher.

## Table of Contents

- [Task State Model](#task-state-model)
- [Scheduling Rules](#scheduling-rules)
- [Workspace Isolation](#workspace-isolation)
- [Merge Protocol](#merge-protocol)
- [Concurrency Control](#concurrency-control)

## Task State Model

Each task progresses through these states:

```
pending -> running -> succeeded -> (merged)
                  \-> failed    -> (dependents blocked)
       \-> blocked (dependency failed)
       \-> skipped (resume mode, already done)
```

| State | Meaning |
|-------|---------|
| `pending` | Not yet started, waiting for turn |
| `running` | Currently being executed by a sub-agent |
| `succeeded` | Execution completed, file scope verified |
| `failed` | Execution failed or scope violation, retries exhausted |
| `blocked` | Upstream dependency failed, will not execute |
| `skipped` | Already completed in a prior run (resume mode) |

State transitions are recorded in the status directory and persisted to `run-report.yaml`.

## Scheduling Rules

1. **Phase ordering is strict**: tasks in phase N never start before all phase N-1 tasks reach a terminal state (succeeded, failed, blocked, skipped).
2. **Dependency gates are hard**: a task with `depends_on: [A, B]` starts only when both A and B have status `succeeded`.
3. **Failure cascades immediately**: when a task fails, all transitive dependents are marked `blocked` without waiting for sibling tasks.
4. **Parallel tasks within a phase** may run concurrently only if `parallel: true` in the execution plan and their `files_touched` have zero overlap.
5. **Max concurrency** is capped by `--max-parallel` (default 3).

## Workspace Isolation

Every task executes on its own git branch:

```
main (base)
 |
 +-- agent-launcher/{domain}/{exec-id}     (integration branch)
      |
      +-- agent/{task-id-lower}            (task branch, per task)
```

- The **integration branch** is created from the base branch at launch time and never written to directly by agents.
- Each **task branch** is created from the integration branch. The sub-agent commits only to its task branch.
- After verification, task branches are merged into the integration branch in topological order.

## Merge Protocol

1. Tasks merge in execution plan order (phase 1 first, then phase 2, etc.).
2. Within a phase, tasks merge in task ID order (deterministic).
3. Each merge uses `--no-ff` to preserve task provenance in the git history.
4. If a merge produces a conflict, the merge is aborted and the task is marked `failed`.
5. Failed merges do not affect the integration branch state (it remains at the last successful merge).

## Concurrency Control

- **Low complexity** tasks: eligible for parallel execution.
- **High complexity** tasks: default to serial unless the execution plan explicitly marks them parallel.
- **files_touched overlap**: always blocks parallel execution, regardless of complexity or plan flags.
- The scheduler never launches more than `--max-parallel` tasks simultaneously.
