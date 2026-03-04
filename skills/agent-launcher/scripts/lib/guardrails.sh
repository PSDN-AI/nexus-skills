#!/usr/bin/env bash
# guardrails.sh — Enforce file-scope, dependency, and retry policy
# Sourced by launch.sh; not intended for standalone execution.

# verify_file_scope <repo_dir> <integration_branch> <task_branch> <allowed_files_newline>
# Checks that the task only modified files within its declared files_touched.
# Returns 0 if clean, 1 if out-of-scope files found.
verify_file_scope() {
  local repo_dir="$1"
  local integration_branch="$2"
  local task_branch="$3"
  local allowed_files="$4"

  local actual_files
  actual_files=$(get_branch_diff_files "$repo_dir" "$integration_branch" "$task_branch")

  if [[ -z "$actual_files" ]]; then
    # No files changed — task may have made no commits
    return 0
  fi

  local violations=""

  while IFS= read -r changed_file; do
    [[ -z "$changed_file" ]] && continue

    local allowed=false
    while IFS= read -r permitted; do
      [[ -z "$permitted" ]] && continue
      # Exact match or directory prefix match (for paths ending in /)
      if [[ "$changed_file" == "$permitted" ]]; then
        allowed=true
        break
      fi
      # Directory-style match: if permitted ends with /, check prefix
      if [[ "$permitted" == */ ]] && [[ "$changed_file" == "${permitted}"* ]]; then
        allowed=true
        break
      fi
    done <<< "$allowed_files"

    if [[ "$allowed" == "false" ]]; then
      violations="${violations}${changed_file}
"
    fi
  done <<< "$actual_files"

  if [[ -n "$violations" ]]; then
    echo "Error: Task modified files outside declared scope:" >&2
    echo "$violations" | while IFS= read -r f; do
      [[ -n "$f" ]] && echo "  - ${f}" >&2
    done
    return 1
  fi

  return 0
}

# check_deps_satisfied <task_id> <deps_space_separated> <status_dir>
# Returns 0 if all dependencies have status "succeeded", 1 otherwise.
check_deps_satisfied() {
  local task_id="$1"
  local deps="$2"
  local status_dir="$3"

  for dep in $deps; do
    local dep_status_file="${status_dir}/${dep}.status"
    if [[ ! -f "$dep_status_file" ]]; then
      echo "Error: Dependency ${dep} for ${task_id} has no status record" >&2
      return 1
    fi
    local dep_status
    dep_status=$(cat "$dep_status_file")
    if [[ "$dep_status" != "succeeded" ]]; then
      echo "Error: Dependency ${dep} for ${task_id} has status: ${dep_status}" >&2
      return 1
    fi
  done

  return 0
}

# should_retry <task_id> <current_retries> <max_retries>
# Returns 0 if the task should be retried, 1 if policy exhausted.
should_retry() {
  local task_id="$1"
  local current_retries="$2"
  local max_retries="${3:-2}"

  if [[ "$current_retries" -lt "$max_retries" ]]; then
    return 0
  fi

  echo "Error: Task ${task_id} exhausted retry limit (${current_retries}/${max_retries})" >&2
  return 1
}

# record_task_status <status_dir> <task_id> <status>
# Writes task status to a file for tracking. Status: pending|running|succeeded|failed|blocked|skipped
record_task_status() {
  local status_dir="$1"
  local task_id="$2"
  local status="$3"

  mkdir -p "$status_dir"
  echo "$status" > "${status_dir}/${task_id}.status"
}

# get_task_status <status_dir> <task_id>
# Outputs current status. Returns "pending" if no record exists.
get_task_status() {
  local status_dir="$1"
  local task_id="$2"

  local status_file="${status_dir}/${task_id}.status"
  if [[ -f "$status_file" ]]; then
    cat "$status_file"
  else
    echo "pending"
  fi
}

# mark_dependents_blocked <tasks_yaml> <failed_task_id> <status_dir>
# Marks all transitive dependents of a failed task as "blocked".
mark_dependents_blocked() {
  local tasks_file="$1"
  local failed_id="$2"
  local status_dir="$3"

  while IFS= read -r tid; do
    local deps
    deps=$(get_task_deps "$tasks_file" "$tid")

    for dep in $deps; do
      if [[ "$dep" == "$failed_id" ]]; then
        local current
        current=$(get_task_status "$status_dir" "$tid")
        if [[ "$current" == "pending" ]]; then
          record_task_status "$status_dir" "$tid" "blocked"
          # Recursively block dependents of this task
          mark_dependents_blocked "$tasks_file" "$tid" "$status_dir"
        fi
        break
      fi
    done
  done < <(get_all_task_ids "$tasks_file")
}
