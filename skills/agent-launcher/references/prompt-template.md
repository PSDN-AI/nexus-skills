# Prompt Template

Standard format for sub-agent launch prompts and handoff notes.

## Table of Contents

- [Task Launch Prompt](#task-launch-prompt)
- [Handoff Note Format](#handoff-note-format)

## Task Launch Prompt

Each sub-agent receives a prompt file at `.agent-launcher/{task-id}.prompt.md`:

```markdown
# Task: {TASK_ID} -- {TASK_NAME}

## Instructions

{prompt_context from tasks.yaml}

## Constraints

- Only modify files listed in the task's `files_touched` declaration.
- Commit your changes with a message starting with: `{TASK_ID}:`
- Do not modify files outside your declared scope.
- Maximum iterations: {max_iterations from config.yaml}

## Declared File Scope

The following files are within scope for this task:

{files_touched list, one per line}

## Acceptance Criteria

This task must satisfy:

{acceptance_criteria IDs from tasks.yaml}

## Context

- Domain: {domain}
- Estimated complexity: {estimated_complexity}
- Dependencies completed: {depends_on task IDs, all succeeded}
- Integration branch: {integration_branch}
- Your working branch: agent/{task-id-lower}
```

### Prompt Rules

1. The prompt must be self-contained. The sub-agent has no access to other tasks or the full spec.
2. `prompt_context` is copied verbatim from tasks.yaml.
3. File scope is explicitly listed so the agent knows its boundaries.
4. The commit message prefix (`{TASK_ID}:`) enables traceability in the integration branch.

## Handoff Note Format

When execution completes, the launcher prints a handoff summary:

```markdown
## Agent Launcher Run: {execution_id}

### Succeeded ({N} tasks)
- {TASK_ID}: {task_name} (merged to integration branch)

### Failed ({N} tasks)
- {TASK_ID}: {task_name} -- {failure reason}

### Blocked ({N} tasks)
- {TASK_ID}: {task_name} -- blocked by {dependency task IDs}

### Next Steps
- Review failed tasks and their error logs
- Fix root cause and re-run with: --resume {execution_id}
- Integration branch: {integration_branch}
```

This format is designed for copy-paste into a PR description or issue comment.
