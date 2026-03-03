#!/usr/bin/env bash
# runner.sh — Invoke sub-agent with prompt_context and task scope
# Sourced by launch.sh; not intended for standalone execution.

# run_task <repo_dir> <task_id> <task_name> <prompt_context> <branch_name> <max_iterations>
# Executes a task by setting up the branch and simulating agent invocation.
# Returns 0 on success, 4 on execution failure.
run_task() {
  local repo_dir="$1"
  local task_id="$2"
  local task_name="$3"
  local prompt_context="$4"
  local branch_name="$5"
  local max_iterations="${6:-3}"

  # Switch to task branch
  checkout_task_branch "$repo_dir" "$branch_name" || return 3

  # Write prompt file for the sub-agent
  local prompt_file="${repo_dir}/.agent-launcher/${task_id}.prompt.md"
  mkdir -p "$(dirname "$prompt_file")"

  cat > "$prompt_file" <<PROMPT
# Task: ${task_id} — ${task_name}

## Instructions

${prompt_context}

## Constraints

- Only modify files listed in the task's \`files_touched\` declaration.
- Commit your changes with a message starting with: \`${task_id}:\`
- Do not modify files outside your declared scope.
- Maximum iterations: ${max_iterations}
PROMPT

  # In real execution, this is where the sub-agent would be invoked.
  # For the skill framework, we document the invocation contract and
  # provide the prompt file for manual or automated agent launch.
  #
  # The agent reads the prompt file, performs the work, and commits
  # to the task branch. The guardrails module then verifies the output.

  return 0
}

# simulate_task_execution <repo_dir> <task_id> <branch_name> <files_touched_list>
# Creates placeholder commits for testing. Not used in production.
# files_touched_list is newline-separated list of files.
simulate_task_execution() {
  local repo_dir="$1"
  local task_id="$2"
  local branch_name="$3"
  local files_list="$4"

  checkout_task_branch "$repo_dir" "$branch_name" || return 3

  # Create placeholder files
  while IFS= read -r filepath; do
    [[ -z "$filepath" ]] && continue
    mkdir -p "$(dirname "${repo_dir}/${filepath}")"
    echo "// ${task_id}: placeholder for ${filepath}" > "${repo_dir}/${filepath}"
  done <<< "$files_list"

  # Commit changes
  git -C "$repo_dir" add -A 2>/dev/null
  git -C "$repo_dir" commit -m "${task_id}: implement ${task_id}" --allow-empty 2>/dev/null || true

  return 0
}

# get_task_commit_sha <repo_dir> <branch_name>
# Outputs the HEAD commit SHA of a task branch.
get_task_commit_sha() {
  local repo_dir="$1"
  local branch_name="$2"

  git -C "$repo_dir" rev-parse "$branch_name" 2>/dev/null
}
