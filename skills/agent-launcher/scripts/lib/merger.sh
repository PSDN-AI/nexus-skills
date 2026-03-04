#!/usr/bin/env bash
# merger.sh — Merge validated task output into integration branch
# Sourced by launch.sh; not intended for standalone execution.

# merge_task_to_integration <integration_worktree> <task_branch> <task_id>
# Merges a task branch into the checked-out integration worktree.
# Returns 0 on merge, 10 when already merged, 5 on merge failure.
merge_task_to_integration() {
  local integration_worktree="$1"
  local task_branch="$2"
  local task_id="$3"

  if git -C "$integration_worktree" merge-base --is-ancestor "$task_branch" HEAD >/dev/null 2>/dev/null; then
    return 10
  fi

  # Merge task branch with a merge commit
  if ! git -C "$integration_worktree" merge --no-ff "$task_branch" \
       -m "Merge ${task_id} into integration branch" >/dev/null 2>/dev/null; then
    echo "Error: Merge conflict when merging ${task_id}" >&2
    # Abort the merge to leave integration branch clean
    git -C "$integration_worktree" merge --abort 2>/dev/null || true
    return 5
  fi

  return 0
}

# merge_tasks_in_order <repo_dir> <integration_worktree> <task_ids_space_separated> <status_dir> <tasks_yaml>
# Merges multiple tasks into the integration branch in the given order.
# Only merges tasks with status "succeeded". Returns "merged:failures".
merge_tasks_in_order() {
  local repo_dir="$1"
  local integration_worktree="$2"
  local task_ids="$3"
  local status_dir="$4"
  local tasks_file="$5"

  local merged=0 failures=0

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
      echo "Error: Task branch not found for ${tid}" >&2
      record_task_status "$status_dir" "$tid" "failed"
      record_task_reason "$status_dir" "$tid" "Task branch not found for merge"
      mark_dependents_blocked "$tasks_file" "$tid" "$status_dir"
      failures=$((failures + 1))
      continue
    fi

    local merge_exit=0
    merge_task_to_integration "$integration_worktree" "$task_branch" "$tid" || merge_exit=$?

    if [[ "$merge_exit" -eq 0 ]]; then
      merged=$((merged + 1))
    elif [[ "$merge_exit" -eq 10 ]]; then
      :
    else
      record_task_status "$status_dir" "$tid" "failed"
      record_task_reason "$status_dir" "$tid" "Merge conflict"
      mark_dependents_blocked "$tasks_file" "$tid" "$status_dir"
      failures=$((failures + 1))
      echo "Error: Failed to merge ${tid}" >&2
    fi
  done

  echo "${merged}:${failures}"
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
