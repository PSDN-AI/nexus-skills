# Failure Policy

Retry, block, resume, and escalation rules for agent-launcher.

## Table of Contents

- [Retry Policy](#retry-policy)
- [Blocking Rules](#blocking-rules)
- [Resume Behavior](#resume-behavior)
- [Escalation and Handoff](#escalation-and-handoff)
- [Stop Conditions](#stop-conditions)

## Retry Policy

| Parameter | Default | Source |
|-----------|---------|--------|
| Max retries per task | `max_iterations` from config.yaml | Configurable |
| Retry delay | None (immediate) | Fixed |
| Retry scope | Same branch, clean state | Automatic |

When a task fails:

1. Increment the retry counter.
2. If retries < `max_iterations`, reset the task branch to its pre-execution state and re-run.
3. If retries >= `max_iterations`, mark the task as `failed` and stop retrying.

Retries are appropriate for transient failures (network timeouts, flaky tests). They are NOT appropriate for:
- File scope violations (deterministic failure, retrying won't help)
- Missing dependencies (structural issue)
- Merge conflicts (requires human intervention)

## Blocking Rules

When a task reaches terminal `failed` state:

1. All direct dependents are marked `blocked`.
2. All transitive dependents (dependents of dependents) are also marked `blocked`.
3. Blocking is immediate — sibling tasks in the same phase continue to run.
4. Blocked tasks are never executed, even if other dependencies succeed.

Example:
```
A (failed) -> B (blocked) -> D (blocked)
           -> C (blocked)
```

## Resume Behavior

When `--resume <execution-id>` is provided:

1. Load the existing `run-report.yaml` for that execution ID.
2. Tasks with `status: succeeded` are marked `skipped` — their branches and commits are preserved.
3. Tasks with `status: failed` are reset to `pending` — they will be re-attempted.
4. Tasks with `status: blocked` are re-evaluated — if their dependencies now succeed, they become eligible.
5. The integration branch is reused, not recreated.

Resume is idempotent: running resume multiple times on a fully succeeded run produces no changes.

## Escalation and Handoff

When the launcher cannot make further progress (all remaining tasks are failed or blocked):

1. Write the final `run-report.yaml` with accurate per-task status.
2. Print a human-readable summary identifying:
   - Which tasks succeeded and were merged
   - Which tasks failed and why
   - Which tasks are blocked and by what
3. Exit with code 4 (task execution failure) if any tasks failed, or code 0 if all succeeded.

The handoff note is designed to be copy-pasted into a PR description or issue comment.

## Stop Conditions

The launcher stops execution when:

| Condition | Action | Exit Code |
|-----------|--------|-----------|
| All tasks succeeded | Generate report, exit | 0 |
| Some tasks failed, rest blocked | Generate report with failure detail | 4 |
| Missing input files | Error message | 1 |
| Invalid tasks.yaml | Validation error | 2 |
| Workspace setup failure | Error message | 3 |
| Merge failure | Mark task failed, continue others | 5 |
| Internal error | Error message | 6 |

The launcher never loops indefinitely. Once all phases are processed and all retries exhausted, it always terminates.
