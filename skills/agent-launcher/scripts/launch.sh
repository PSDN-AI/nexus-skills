#!/usr/bin/env bash
# launch.sh — Main entry point for Agent Launcher
# Usage: launch.sh <domain_dir> [options]
# Executes tasks.yaml as a controlled implementation run
set -euo pipefail

VERSION="0.1.0"

# Require bash 4+ (associative arrays)
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "Error: bash 4.0+ required (found ${BASH_VERSION})." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Source library modules ---
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/scheduler.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/workspace.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/runner.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/guardrails.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/merger.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/reporter.sh"

# --- Defaults ---
DOMAIN_DIR=""
REPO_DIR=""
MAX_PARALLEL=3
DRY_RUN=false
RESUME_ID=""
VERBOSE=false
STATUS_DIR=""
WORKTREE_ROOT=""
INTEGRATION_BRANCH=""
INTEGRATION_WORKTREE=""

show_usage() {
  cat <<EOF
Usage: launch.sh <domain_dir> [options]

Execute tasks.yaml as a controlled implementation run with isolated sub-agents.

Arguments:
  domain_dir            Path to domain folder containing tasks.yaml and config.yaml

Options:
  -r, --repo DIR        Path to target repository checkout
  -p, --max-parallel N  Maximum concurrent tasks (default: 3)
  --dry-run             Preview queue and branch plan without executing
  --resume ID           Resume from a prior run (skip succeeded tasks)
  -v, --verbose         Show detailed processing info
  --version             Print version and exit
  -h, --help            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      echo "agent-launcher ${VERSION}"
      exit 0
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    -r|--repo)
      REPO_DIR="${2:?--repo requires a directory path}"
      shift 2
      ;;
    -p|--max-parallel)
      MAX_PARALLEL="${2:?--max-parallel requires a number}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --resume)
      RESUME_ID="${2:?--resume requires an execution ID}"
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      show_usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$DOMAIN_DIR" ]]; then
        DOMAIN_DIR="$1"
      else
        echo "Error: Unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$DOMAIN_DIR" ]]; then
  echo "Error: Domain directory path is required." >&2
  show_usage >&2
  exit 1
fi

if [[ ! -d "$DOMAIN_DIR" ]]; then
  echo "Error: Domain directory not found: ${DOMAIN_DIR}" >&2
  exit 1
fi

if ! [[ "$MAX_PARALLEL" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --max-parallel must be a positive integer." >&2
  exit 1
fi

DOMAIN_DIR=$(cd "$DOMAIN_DIR" && pwd)

log() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo "[agent-launcher] $*" >&2
  fi
}

# shellcheck disable=SC2317,SC2329
cleanup_temp_state() {
  local path=""

  if [[ -n "$REPO_DIR" ]] && [[ -d "$REPO_DIR/.git" ]] && [[ -n "$WORKTREE_ROOT" ]] && [[ -d "$WORKTREE_ROOT" ]]; then
    while IFS= read -r path; do
      [[ -n "$path" ]] && remove_branch_worktree "$REPO_DIR" "$path"
    done < <(find "$WORKTREE_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)
  fi

  [[ -n "$WORKTREE_ROOT" ]] && rm -rf "$WORKTREE_ROOT"
  [[ -n "$STATUS_DIR" ]] && rm -rf "$STATUS_DIR"
  return 0
}

trap cleanup_temp_state EXIT

compute_timestamp() {
  local format="$1"

  if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
    date -u -d "@${SOURCE_DATE_EPOCH}" "$format" 2>/dev/null \
      || date -u -r "${SOURCE_DATE_EPOCH}" "$format"
  else
    date -u "$format"
  fi
}

compute_next_exec_id() {
  local repo_dir="$1"
  local domain="$2"
  local exec_date="$3"
  local next=1
  local branch=""

  if [[ -n "$repo_dir" ]] && [[ -d "$repo_dir/.git" ]]; then
    while IFS= read -r branch; do
      local suffix
      suffix="${branch##*run-"${exec_date}"-}"
      if [[ "$suffix" =~ ^[0-9]{3}$ ]] && [[ $((10#$suffix)) -ge "$next" ]]; then
        next=$((10#$suffix + 1))
      fi
    done < <(git -C "$repo_dir" for-each-ref \
      --format='%(refname:short)' \
      "refs/heads/agent-launcher/${domain}/run-${exec_date}-*")
  fi

  printf 'run-%s-%03d\n' "$exec_date" "$next"
}

restore_resumed_statuses() {
  local report_file="$1"
  local expected_exec_id="$2"
  local report_exec_id=""
  local current_task=""

  if [[ ! -f "$report_file" ]]; then
    echo "Error: --resume requires an existing run-report.yaml in ${DOMAIN_DIR}" >&2
    return 2
  fi

  report_exec_id=$(grep '^execution_id:' "$report_file" | head -1 | sed 's/.*: *//' | tr -d '"' | tr -d "'")
  if [[ "$report_exec_id" != "$expected_exec_id" ]]; then
    echo "Error: run-report.yaml execution_id (${report_exec_id:-missing}) does not match --resume ${expected_exec_id}" >&2
    return 2
  fi

  while IFS= read -r line; do
    if echo "$line" | grep -q '^  - id:'; then
      current_task=$(echo "$line" | sed 's/.*id: //' | tr -d ' ')
      continue
    fi

    if [[ -n "$current_task" ]] && echo "$line" | grep -q '^    status: succeeded'; then
      record_task_status "$STATUS_DIR" "$current_task" "succeeded"
      log "  Skipping completed: ${current_task}"
      current_task=""
    fi
  done < "$report_file"
}

get_dependency_state() {
  local task_id="$1"
  local deps=""
  local dep=""

  deps=$(get_task_deps "$TASKS_FILE" "$task_id")
  if [[ -z "$deps" ]]; then
    echo "ready"
    return 0
  fi

  for dep in $deps; do
    local dep_status
    dep_status=$(get_task_status "$STATUS_DIR" "$dep")
    case "$dep_status" in
      succeeded)
        ;;
      failed|blocked)
        echo "blocked"
        return 0
        ;;
      *)
        echo "pending"
        return 0
        ;;
    esac
  done

  echo "ready"
}

prepare_task_branch() {
  local task_id="$1"

  if ! create_task_branch "$REPO_DIR" "$INTEGRATION_BRANCH" "$task_id" "true" >/dev/null; then
    record_task_status "$STATUS_DIR" "$task_id" "failed"
    record_task_reason "$STATUS_DIR" "$task_id" "Workspace preparation failed"
    mark_dependents_blocked "$TASKS_FILE" "$task_id" "$STATUS_DIR"
    return 10
  fi

  return 0
}

execute_task_once() {
  local task_id="$1"
  local task_name=""
  local prompt_context=""
  local files_list=""
  local task_id_lower=""
  local branch_name=""
  local task_worktree=""
  local run_exit=0
  local task_sha=""
  local base_sha=""

  task_name=$(get_task_field "$TASKS_FILE" "$task_id" "name")
  prompt_context=$(get_prompt_context "$TASKS_FILE" "$task_id")
  files_list=$(get_files_touched "$TASKS_FILE" "$task_id")
  task_id_lower=$(echo "$task_id" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
  branch_name="agent/${task_id_lower}"
  task_worktree="${WORKTREE_ROOT}/${task_id_lower}"

  prepare_task_branch "$task_id" || return $?
  remove_branch_worktree "$REPO_DIR" "$task_worktree"
  if ! create_branch_worktree "$REPO_DIR" "$branch_name" "$task_worktree" >/dev/null; then
    record_task_status "$STATUS_DIR" "$task_id" "failed"
    record_task_reason "$STATUS_DIR" "$task_id" "Workspace preparation failed"
    mark_dependents_blocked "$TASKS_FILE" "$task_id" "$STATUS_DIR"
    return 10
  fi

  run_task "$task_worktree" "$task_id" "$task_name" "$prompt_context" "$files_list" "$MAX_ITERATIONS" || run_exit=$?
  if [[ "$run_exit" -ne 0 ]]; then
    remove_branch_worktree "$REPO_DIR" "$task_worktree"
    return 4
  fi

  if ! verify_file_scope "$REPO_DIR" "$INTEGRATION_BRANCH" "$branch_name" "$files_list" 2>/dev/null; then
    record_task_status "$STATUS_DIR" "$task_id" "failed"
    record_task_reason "$STATUS_DIR" "$task_id" "File scope violation"
    mark_dependents_blocked "$TASKS_FILE" "$task_id" "$STATUS_DIR"
    remove_branch_worktree "$REPO_DIR" "$task_worktree"
    return 10
  fi

  task_sha=$(get_task_commit_sha "$task_worktree")
  base_sha=$(git -C "$REPO_DIR" rev-parse "$INTEGRATION_BRANCH" 2>/dev/null || echo "")
  if [[ -z "$task_sha" ]] || [[ "$task_sha" == "$base_sha" ]]; then
    record_task_status "$STATUS_DIR" "$task_id" "failed"
    record_task_reason "$STATUS_DIR" "$task_id" "Task completed without creating a commit"
    mark_dependents_blocked "$TASKS_FILE" "$task_id" "$STATUS_DIR"
    remove_branch_worktree "$REPO_DIR" "$task_worktree"
    return 10
  fi

  record_task_status "$STATUS_DIR" "$task_id" "succeeded"
  record_task_sha "$STATUS_DIR" "$task_id" "$task_sha"
  remove_branch_worktree "$REPO_DIR" "$task_worktree"
  return 0
}

execute_task_with_retries() {
  local task_id="$1"
  local retries=0
  local task_exit=0

  while true; do
    record_task_status "$STATUS_DIR" "$task_id" "running"
    log "    ${task_id}: running..."

    execute_task_once "$task_id" || task_exit=$?
    if [[ "$task_exit" -eq 0 ]]; then
      record_task_retries "$STATUS_DIR" "$task_id" "$retries"
      log "    ${task_id}: succeeded"
      return 0
    fi

    if [[ "$task_exit" -eq 10 ]]; then
      record_task_retries "$STATUS_DIR" "$task_id" "$retries"
      log "    ${task_id}: FAILED"
      return 10
    fi

    retries=$((retries + 1))
    record_task_retries "$STATUS_DIR" "$task_id" "$retries"
    if should_retry "$task_id" "$retries" "$MAX_ITERATIONS" 2>/dev/null; then
      log "    ${task_id}: retrying (${retries}/${MAX_ITERATIONS})"
      task_exit=0
      continue
    fi

    record_task_status "$STATUS_DIR" "$task_id" "failed"
    record_task_reason "$STATUS_DIR" "$task_id" "Execution failed after ${retries} retries"
    mark_dependents_blocked "$TASKS_FILE" "$task_id" "$STATUS_DIR"
    log "    ${task_id}: FAILED"
    return 4
  done
}

run_ready_tasks_serial() {
  local task_id=""
  local task_exit=0

  for task_id in "$@"; do
    task_exit=0
    execute_task_with_retries "$task_id" || task_exit=$?
    if [[ "$task_exit" -ne 0 ]]; then
      TASK_FAILURES=1
    fi
  done
}

run_ready_tasks_parallel() {
  local pending=("$@")
  local batch=()
  local deferred=()
  local selected=""
  local task_id=""
  local safe=""
  local pids=()
  local pid=""
  local wait_exit=0

  while [[ "${#pending[@]}" -gt 0 ]]; do
    batch=()
    deferred=()

    for task_id in "${pending[@]}"; do
      if [[ "${#batch[@]}" -ge "$MAX_PARALLEL" ]]; then
        deferred+=("$task_id")
        continue
      fi

      safe=true
      for selected in "${batch[@]}"; do
        if ! check_parallel_safe "$TASKS_FILE" "$task_id" "$selected"; then
          safe=false
          break
        fi
      done

      if [[ "$safe" == "true" ]]; then
        batch+=("$task_id")
      else
        deferred+=("$task_id")
      fi
    done

    if [[ "${#batch[@]}" -eq 0 ]]; then
      batch=("${pending[0]}")
      deferred=("${pending[@]:1}")
    fi

    pids=()
    for task_id in "${batch[@]}"; do
      execute_task_with_retries "$task_id" &
      pids+=("$!")
    done

    for pid in "${pids[@]}"; do
      wait_exit=0
      wait "$pid" || wait_exit=$?
      if [[ "$wait_exit" -ne 0 ]]; then
        TASK_FAILURES=1
      fi
    done

    pending=("${deferred[@]}")
  done
}

# --- Input files ---
TASKS_FILE="${DOMAIN_DIR}/tasks.yaml"
CONFIG_FILE="${DOMAIN_DIR}/config.yaml"

if [[ ! -f "$TASKS_FILE" ]]; then
  echo "Error: tasks.yaml not found in domain directory: ${DOMAIN_DIR}" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: config.yaml not found in domain directory: ${DOMAIN_DIR}" >&2
  exit 1
fi

# --- Config ---
DOMAIN=$(grep '^domain:' "$CONFIG_FILE" | sed 's/domain: *//' | tr -d '"' | tr -d "'")
TARGET_BRANCH=$(grep '^target_branch:' "$CONFIG_FILE" | sed 's/target_branch: *//' | tr -d '"' | tr -d "'")
MAX_ITERATIONS=$(grep '^max_iterations:' "$CONFIG_FILE" | sed 's/max_iterations: *//' | tr -d '"' | tr -d "'")

TARGET_BRANCH="${TARGET_BRANCH:-main}"
MAX_ITERATIONS="${MAX_ITERATIONS:-3}"
TIMESTAMP=$(compute_timestamp '+%Y-%m-%dT%H:%M:%SZ')
EXEC_DATE=$(compute_timestamp '+%Y%m%d')

log "Domain: ${DOMAIN}"
log "Tasks file: ${TASKS_FILE}"

# ============================================================
# Phase 1: LOAD
# ============================================================
log "Phase 1: Loading tasks..."

TOTAL_TASKS=$(grep -c '^  - id:' "$TASKS_FILE" 2>/dev/null || echo "0")
TOTAL_PHASES=$(grep -c '^  - phase:' "$TASKS_FILE" 2>/dev/null || echo "0")

if [[ "$TOTAL_TASKS" -eq 0 ]]; then
  echo "Error: No tasks found in tasks.yaml" >&2
  exit 2
fi

# ============================================================
# Phase 2: VALIDATE
# ============================================================
log "Phase 2: Validating prerequisites..."

if [[ -n "$REPO_DIR" ]]; then
  if [[ "$DRY_RUN" != "true" ]]; then
    if [[ ! -d "$REPO_DIR" ]]; then
      echo "Error: Repository directory not found: ${REPO_DIR}" >&2
      exit 2
    fi
    if [[ ! -d "${REPO_DIR}/.git" ]]; then
      echo "Error: Not a git repository: ${REPO_DIR}" >&2
      exit 2
    fi
    REPO_DIR=$(cd "$REPO_DIR" && pwd)
  elif [[ -d "$REPO_DIR" ]] && [[ -d "${REPO_DIR}/.git" ]]; then
    REPO_DIR=$(cd "$REPO_DIR" && pwd)
  fi
fi

if [[ -n "$RESUME_ID" ]]; then
  EXEC_ID="$RESUME_ID"
else
  EXEC_ID=$(compute_next_exec_id "$REPO_DIR" "$DOMAIN" "$EXEC_DATE")
fi

INTEGRATION_BRANCH="agent-launcher/${DOMAIN}/${EXEC_ID}"
log "Execution ID: ${EXEC_ID}"

if [[ "$DRY_RUN" != "true" ]]; then
  if [[ -z "$REPO_DIR" ]]; then
    echo "Error: --repo is required for execution (use --dry-run to preview without a repo)" >&2
    exit 2
  fi

  if ! branch_exists "$REPO_DIR" "$TARGET_BRANCH"; then
    echo "Error: Base branch not found: ${TARGET_BRANCH}" >&2
    exit 2
  fi

  if ! is_repo_clean "$REPO_DIR"; then
    echo "Error: Repository working tree must be clean before launch." >&2
    exit 2
  fi

  if [[ "${AGENT_LAUNCHER_SIMULATE:-false}" != "true" ]] && [[ -z "${AGENT_LAUNCHER_EXECUTOR:-}" ]]; then
    echo "Error: No task executor configured. Set AGENT_LAUNCHER_EXECUTOR or AGENT_LAUNCHER_SIMULATE=true." >&2
    exit 4
  fi
fi

# ============================================================
# Phase 3: SCHEDULE
# ============================================================
log "Phase 3: Building execution schedule..."

STATUS_DIR=$(mktemp -d)
WORKTREE_ROOT=$(mktemp -d)

if [[ -n "$RESUME_ID" ]]; then
  restore_resumed_statuses "${DOMAIN_DIR}/run-report.yaml" "$RESUME_ID" || exit $?
  if [[ -n "$REPO_DIR" ]] && [[ ! -d "$REPO_DIR/.git" ]]; then
    echo "Error: Invalid repository for resume." >&2
    exit 2
  fi
fi

# ============================================================
# DRY RUN
# ============================================================
if [[ "$DRY_RUN" == "true" ]]; then
  echo "Agent Launcher — Dry Run"
  echo "========================"
  echo ""
  echo "Domain:             ${DOMAIN}"
  echo "Tasks:              ${TOTAL_TASKS}"
  echo "Phases:             ${TOTAL_PHASES}"
  echo "Max parallel:       ${MAX_PARALLEL}"
  echo "Integration branch: ${INTEGRATION_BRANCH}"

  if [[ -n "$REPO_DIR" ]]; then
    echo "Target repo:        ${REPO_DIR}"
    echo "Base branch:        ${TARGET_BRANCH}"
  fi

  echo ""
  echo "Execution Plan:"

  while IFS= read -r phase_line; do
    phase_num=$(echo "$phase_line" | cut -d: -f1)
    parallel=$(echo "$phase_line" | cut -d: -f2)
    tasks_csv=$(echo "$phase_line" | cut -d: -f3)

    mode="serial"
    [[ "$parallel" == "true" ]] && mode="parallel"

    echo ""
    echo "  Phase ${phase_num} (${mode}):"
    echo "$tasks_csv" | tr ',' '\n' | while IFS= read -r tid; do
      task_name=$(get_task_field "$TASKS_FILE" "$tid" "name")
      complexity=$(get_task_field "$TASKS_FILE" "$tid" "estimated_complexity")
      task_id_lower=$(echo "$tid" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
      printf "    %-10s %-40s [%s]  -> branch: agent/%s\n" "$tid" "$task_name" "$complexity" "$task_id_lower"
    done
  done < <(get_execution_phases "$TASKS_FILE")

  echo ""
  echo "No changes made (dry run)."
  exit 0
fi

# ============================================================
# Phase 4: PREPARE
# ============================================================
log "Phase 4: Preparing workspaces..."

STARTED_AT="$TIMESTAMP"

if [[ -n "$RESUME_ID" ]]; then
  if ! branch_exists "$REPO_DIR" "$INTEGRATION_BRANCH"; then
    echo "Error: Integration branch not found for resume: ${INTEGRATION_BRANCH}" >&2
    exit 2
  fi
else
  create_integration_branch "$REPO_DIR" "$TARGET_BRANCH" "$EXEC_ID" "$DOMAIN" >/dev/null || exit 3
  log "Created integration branch: ${INTEGRATION_BRANCH}"
fi

INTEGRATION_WORKTREE="${WORKTREE_ROOT}/integration"
create_branch_worktree "$REPO_DIR" "$INTEGRATION_BRANCH" "$INTEGRATION_WORKTREE" >/dev/null || exit 3

# ============================================================
# Phase 5-7: EXECUTE + VERIFY + MERGE
# ============================================================
log "Phase 5-7: Executing tasks..."

TASK_FAILURES=0
MERGE_FAILURES=0
MERGED_COUNT=0

while IFS= read -r phase_line; do
  phase_num=$(echo "$phase_line" | cut -d: -f1)
  parallel=$(echo "$phase_line" | cut -d: -f2)
  tasks_csv=$(echo "$phase_line" | cut -d: -f3)
  phase_tasks=()
  ready_tasks=()

  log "  Executing phase ${phase_num}..."

  while IFS= read -r task_id; do
    [[ -z "$task_id" ]] && continue
    phase_tasks+=("$task_id")

    current_status=$(get_task_status "$STATUS_DIR" "$task_id")
    if [[ "$current_status" == "succeeded" ]] || [[ "$current_status" == "blocked" ]] || [[ "$current_status" == "skipped" ]]; then
      log "    ${task_id}: skipping (${current_status})"
      continue
    fi

    dep_state=$(get_dependency_state "$task_id")
    case "$dep_state" in
      ready)
        ready_tasks+=("$task_id")
        ;;
      blocked)
        record_task_status "$STATUS_DIR" "$task_id" "blocked"
        record_task_reason "$STATUS_DIR" "$task_id" "Dependency not satisfied"
        mark_dependents_blocked "$TASKS_FILE" "$task_id" "$STATUS_DIR"
        TASK_FAILURES=1
        log "    ${task_id}: blocked (dependency failed)"
        ;;
      *)
        record_task_status "$STATUS_DIR" "$task_id" "blocked"
        record_task_reason "$STATUS_DIR" "$task_id" "Dependency not ready for current phase"
        mark_dependents_blocked "$TASKS_FILE" "$task_id" "$STATUS_DIR"
        TASK_FAILURES=1
        log "    ${task_id}: blocked (dependency not ready)"
        ;;
    esac
  done < <(echo "$tasks_csv" | tr ',' '\n')

  if [[ "${#ready_tasks[@]}" -gt 0 ]]; then
    if [[ "$parallel" == "true" ]]; then
      run_ready_tasks_parallel "${ready_tasks[@]}"
    else
      run_ready_tasks_serial "${ready_tasks[@]}"
    fi
  fi

  merge_result=$(merge_tasks_in_order \
    "$REPO_DIR" \
    "$INTEGRATION_WORKTREE" \
    "$(printf '%s ' "${phase_tasks[@]}")" \
    "$STATUS_DIR" \
    "$TASKS_FILE")
  phase_merged="${merge_result%%:*}"
  phase_merge_failures="${merge_result##*:}"
  MERGED_COUNT=$((MERGED_COUNT + phase_merged))

  if [[ "$phase_merge_failures" -gt 0 ]]; then
    MERGE_FAILURES=$((MERGE_FAILURES + phase_merge_failures))
  fi

  log "  Phase ${phase_num}: merged ${phase_merged} task(s)"
done < <(get_execution_phases "$TASKS_FILE")

# ============================================================
# Phase 8: REPORT
# ============================================================
log "Phase 8: Generating report..."

FINISHED_AT=$(compute_timestamp '+%Y-%m-%dT%H:%M:%SZ')
REPORT_FILE="${DOMAIN_DIR}/run-report.yaml"

generate_run_report "$REPORT_FILE" "$TASKS_FILE" "$STATUS_DIR" \
  "$EXEC_ID" "$DOMAIN" "${REPO_DIR}" "$TARGET_BRANCH" \
  "$INTEGRATION_BRANCH" "$STARTED_AT" "$FINISHED_AT" "$MERGED_COUNT"

echo "Agent Launcher — Execution Complete"
echo "===================================="
echo ""
echo "Domain:             ${DOMAIN}"
echo "Execution ID:       ${EXEC_ID}"
echo "Integration branch: ${INTEGRATION_BRANCH}"
echo "Report:             ${REPORT_FILE}"

print_human_summary "$REPORT_FILE"

if [[ "$MERGE_FAILURES" -gt 0 ]]; then
  exit 5
fi

if [[ "$TASK_FAILURES" -gt 0 ]]; then
  exit 4
fi

exit 0
