#!/usr/bin/env bash
# workspace.sh — Create isolated branches/worktrees per task
# Sourced by launch.sh; not intended for standalone execution.

# create_integration_branch <repo_dir> <base_branch> <execution_id> <domain>
# Creates the integration branch for merging task results.
# Outputs the branch name.
create_integration_branch() {
  local repo_dir="$1"
  local base_branch="$2"
  local exec_id="$3"
  local domain="$4"

  local branch_name="agent-launcher/${domain}/${exec_id}"

  git -C "$repo_dir" branch "$branch_name" "$base_branch" 2>/dev/null || {
    echo "Error: Failed to create integration branch: ${branch_name}" >&2
    return 3
  }

  echo "$branch_name"
}

# create_task_branch <repo_dir> <integration_branch> <task_id> [reset_existing]
# Creates an isolated branch for a single task's work.
# Outputs the branch name.
create_task_branch() {
  local repo_dir="$1"
  local integration_branch="$2"
  local task_id="$3"
  local reset_existing="${4:-false}"

  local task_id_lower
  task_id_lower=$(echo "$task_id" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
  local branch_name="agent/${task_id_lower}"

  if branch_exists "$repo_dir" "$branch_name"; then
    if [[ "$reset_existing" == "true" ]]; then
      git -C "$repo_dir" branch -f "$branch_name" "$integration_branch" 2>/dev/null || {
        echo "Error: Failed to reset task branch: ${branch_name}" >&2
        return 3
      }
    fi
  else
    git -C "$repo_dir" branch "$branch_name" "$integration_branch" 2>/dev/null || {
      echo "Error: Failed to create task branch: ${branch_name}" >&2
      return 3
    }
  fi

  echo "$branch_name"
}

# create_branch_worktree <repo_dir> <branch_name> <worktree_path>
# Creates a worktree checked out to the given branch.
create_branch_worktree() {
  local repo_dir="$1"
  local branch_name="$2"
  local worktree_path="$3"

  mkdir -p "$(dirname "$worktree_path")"
  git -C "$repo_dir" worktree add --force "$worktree_path" "$branch_name" >/dev/null 2>&1 || {
    echo "Error: Failed to create worktree for branch: ${branch_name}" >&2
    return 3
  }

  echo "$worktree_path"
}

# remove_branch_worktree <repo_dir> <worktree_path>
# Removes a worktree path and prunes stale worktree metadata.
remove_branch_worktree() {
  local repo_dir="$1"
  local worktree_path="$2"

  git -C "$repo_dir" worktree remove --force "$worktree_path" >/dev/null 2>&1 || true
  git -C "$repo_dir" worktree prune >/dev/null 2>&1 || true
}

# get_branch_diff_files <repo_dir> <base_branch> <task_branch>
# Outputs files changed on the task branch relative to base.
get_branch_diff_files() {
  local repo_dir="$1"
  local base_branch="$2"
  local task_branch="$3"

  git -C "$repo_dir" diff --name-only "${base_branch}...${task_branch}" 2>/dev/null
}

# is_repo_clean <repo_dir>
# Returns 0 if the working tree is clean, 1 otherwise.
is_repo_clean() {
  local repo_dir="$1"

  if [[ -z "$(git -C "$repo_dir" status --porcelain --untracked-files=normal 2>/dev/null)" ]]; then
    return 0
  fi
  return 1
}

# get_current_branch <repo_dir>
# Outputs the current branch name.
get_current_branch() {
  local repo_dir="$1"
  git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null
}

# branch_exists <repo_dir> <branch_name>
# Returns 0 if branch exists, 1 otherwise.
branch_exists() {
  local repo_dir="$1"
  local branch_name="$2"

  git -C "$repo_dir" show-ref --verify --quiet "refs/heads/${branch_name}"
}
