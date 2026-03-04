#!/usr/bin/env bash
# runner.sh — Invoke sub-agent with prompt_context and task scope
# Sourced by launch.sh; not intended for standalone execution.

# run_task <repo_dir> <task_id> <task_name> <prompt_context> <files_list> <max_iterations>
# Executes a task by writing the prompt file and invoking the configured executor.
# Returns 0 on success, 4 on execution failure.
run_task() {
  local repo_dir="$1"
  local task_id="$2"
  local task_name="$3"
  local prompt_context="$4"
  local files_list="$5"
  local max_iterations="${6:-3}"

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

  if [[ "${AGENT_LAUNCHER_SIMULATE:-false}" == "true" ]]; then
    simulate_task_execution "$repo_dir" "$task_id" "$files_list"
    return $?
  fi

  if [[ -z "${AGENT_LAUNCHER_EXECUTOR:-}" ]]; then
    echo "Error: No task executor configured. Set AGENT_LAUNCHER_EXECUTOR or AGENT_LAUNCHER_SIMULATE=true." >&2
    return 4
  fi

  (
    cd "$repo_dir" || exit 4
    export AGENT_LAUNCHER_REPO_DIR="$repo_dir"
    export AGENT_LAUNCHER_TASK_ID="$task_id"
    export AGENT_LAUNCHER_TASK_NAME="$task_name"
    export AGENT_LAUNCHER_PROMPT_FILE="$prompt_file"
    export AGENT_LAUNCHER_FILES_TOUCHED="$files_list"
    export AGENT_LAUNCHER_MAX_ITERATIONS="$max_iterations"
    bash -lc "$AGENT_LAUNCHER_EXECUTOR"
  ) || return 4

  return 0
}

# simulate_task_execution <repo_dir> <task_id> <files_touched_list>
# Creates placeholder commits for testing. Not used in production.
# files_touched_list is newline-separated list of files.
simulate_task_execution() {
  local repo_dir="$1"
  local task_id="$2"
  local files_list="$3"

  # Create placeholder files
  while IFS= read -r filepath; do
    [[ -z "$filepath" ]] && continue
    mkdir -p "$(dirname "${repo_dir}/${filepath}")"
    echo "// ${task_id}: placeholder for ${filepath}" > "${repo_dir}/${filepath}"
    git -C "$repo_dir" add -- "$filepath" 2>/dev/null || return 4
  done <<< "$files_list"

  # Commit changes
  git -C "$repo_dir" commit -m "${task_id}: implement ${task_id}" --allow-empty 2>/dev/null || return 4

  return 0
}

# get_task_commit_sha <repo_dir>
# Outputs the HEAD commit SHA of a checked-out task worktree.
get_task_commit_sha() {
  local repo_dir="$1"
  git -C "$repo_dir" rev-parse HEAD 2>/dev/null
}
