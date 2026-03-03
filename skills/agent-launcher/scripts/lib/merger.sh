#!/usr/bin/env bash
# merger.sh — Merge validated task output into integration branch
# Sourced by launch.sh; not intended for standalone execution.

# merge_task_to_integration <repo_dir> <integration_branch> <task_branch> <task_id>
# Merges a task branch into the integration branch.
# Returns 0 on success, 5 on merge failure.
merge_task_to_integration() {
  local repo_dir="$1"
  local integration_branch="$2"
  local task_branch="$3"
  local task_id="$4"

  # Switch to integration branch
  git -C "$repo_dir" checkout "$integration_branch" 2>/dev/null || {
    echo "Error: Failed to checkout integration branch: ${integration_branch}" >&2
    return 5
  }

  # Merge task branch with a merge commit
  if ! git -C "$repo_dir" merge --no-ff "$task_branch" \
       -m "Merge ${task_id} into integration branch" 2>/dev/null; then
    echo "Error: Merge conflict when merging ${task_id}" >&2
    # Abort the merge to leave integration branch clean
    git -C "$repo_dir" merge --abort 2>/dev/null || true
    return 5
  fi

  return 0
}

# merge_tasks_in_order <repo_dir> <integration_branch> <task_ids_space_separated> <status_dir>
# Merges multiple tasks into the integration branch in the given order.
# Only merges tasks with status "succeeded". Returns count of merged tasks.
merge_tasks_in_order() {
  local repo_dir="$1"
  local integration_branch="$2"
  local task_ids="$3"
  local status_dir="$4"

  local merged=0

  for tid in $task_ids; do
    local status
    status=$(get_task_status "$status_dir" "$tid")

    if [[ "$status" != "succeeded" ]]; then
      continue
    fi

    local task_id_lower
    task_id_lower=$(echo "$tid" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    local task_branch="agent/${task_id_lower}"

    if ! branch_exists "$repo_dir" "$task_branch"; then
      echo "Warning: Task branch not found for ${tid}, skipping merge" >&2
      continue
    fi

    if merge_task_to_integration "$repo_dir" "$integration_branch" "$task_branch" "$tid"; then
      merged=$((merged + 1))
    else
      echo "Error: Failed to merge ${tid}" >&2
    fi
  done

  echo "$merged"
}

# get_merge_order <tasks_yaml>
# Outputs task IDs in topological merge order (respecting dependencies).
get_merge_order() {
  local tasks_file="$1"

  # Use execution_plan phases for merge ordering
  while IFS= read -r phase_line; do
    local tasks_csv
    tasks_csv=$(echo "$phase_line" | cut -d: -f3)
    echo "$tasks_csv" | tr ',' '\n'
  done < <(get_execution_phases "$tasks_file")
}
