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
| Retry scope | Same branch, reset to current integration branch tip | Automatic |

When a task fails:

1. Increment the retry counter.
2. If retries < `max_iterations`, reset the task branch to the current integration branch tip, recreate the task worktree, and re-run.
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
4. Tasks whose dependencies are not satisfied by the current phase are also marked `blocked` for the current run.
5. Blocked tasks are never executed in that run, even if other dependencies succeed later.

Example:
```
A (failed) -> B (blocked) -> D (blocked)
           -> C (blocked)
```

## Resume Behavior

When `--resume <execution-id>` is provided:

1. Load the existing `run-report.yaml` for that execution ID.
2. Reject resume if `run-report.yaml` is missing or its `execution_id` does not match the requested ID.
3. Tasks with `status: succeeded` are restored as `succeeded` and skipped by the scheduler.
4. Tasks with `status: failed` are reset to `pending` — they will be re-attempted.
5. Tasks with `status: blocked` are re-evaluated from dependency state in the new run.
6. The integration branch is reused, not recreated.

Resume is idempotent: running resume multiple times on a fully succeeded run produces no changes.

## Escalation and Handoff

When the launcher cannot make further progress (all remaining tasks are failed or blocked):

1. Write the final `run-report.yaml` with accurate per-task status.
2. Print a human-readable summary identifying:
   - Which tasks succeeded and were merged
   - Which tasks failed and why
   - Which tasks are blocked and by what
3. Exit with code 5 if any merge failed.
4. Otherwise exit with code 4 if any tasks failed or were blocked, or code 0 if all tasks succeeded.

The handoff note is designed to be copy-pasted into a PR description or issue comment.

## Stop Conditions

The launcher stops execution when:

| Condition | Action | Exit Code |
|-----------|--------|-----------|
| All tasks succeeded | Generate report, exit | 0 |
| Some tasks failed, rest blocked | Generate report with failure detail | 4 |
| Missing input files | Error message | 1 |
| Invalid tasks.yaml or repo state | Validation error | 2 |
| Workspace setup failure | Error message | 3 |
| Merge failure | Mark task failed, continue others, then exit after report | 5 |

The launcher never loops indefinitely. Once all phases are processed and all retries exhausted, it always terminates.
