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

# --- Parse arguments ---
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

# --- Validate inputs ---
if [[ -z "$DOMAIN_DIR" ]]; then
  echo "Error: Domain directory path is required." >&2
  show_usage >&2
  exit 1
fi

if [[ ! -d "$DOMAIN_DIR" ]]; then
  echo "Error: Domain directory not found: ${DOMAIN_DIR}" >&2
  exit 1
fi

DOMAIN_DIR=$(cd "$DOMAIN_DIR" && pwd)

log() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo "[agent-launcher] $*" >&2
  fi
}

# Check required files
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

# Parse config
DOMAIN=$(grep '^domain:' "$CONFIG_FILE" | sed 's/domain: *//' | tr -d '"' | tr -d "'")
TARGET_BRANCH=$(grep '^target_branch:' "$CONFIG_FILE" | sed 's/target_branch: *//' | tr -d '"' | tr -d "'")
MAX_ITERATIONS=$(grep '^max_iterations:' "$CONFIG_FILE" | sed 's/max_iterations: *//' | tr -d '"' | tr -d "'")

TARGET_BRANCH="${TARGET_BRANCH:-main}"
MAX_ITERATIONS="${MAX_ITERATIONS:-3}"

# Support SOURCE_DATE_EPOCH for reproducible output
if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
  TIMESTAMP=$(date -u -d "@${SOURCE_DATE_EPOCH}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u -r "${SOURCE_DATE_EPOCH}" '+%Y-%m-%dT%H:%M:%SZ')
  EXEC_DATE=$(date -u -d "@${SOURCE_DATE_EPOCH}" '+%Y%m%d' 2>/dev/null \
    || date -u -r "${SOURCE_DATE_EPOCH}" '+%Y%m%d')
else
  TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  EXEC_DATE=$(date -u '+%Y%m%d')
fi

EXEC_ID="${RESUME_ID:-run-${EXEC_DATE}-001}"
INTEGRATION_BRANCH="agent-launcher/${DOMAIN}/${EXEC_ID}"

log "Domain: ${DOMAIN}"
log "Tasks file: ${TASKS_FILE}"
log "Execution ID: ${EXEC_ID}"

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

if [[ -n "$REPO_DIR" ]] && [[ "$DRY_RUN" != "true" ]]; then
  if [[ ! -d "$REPO_DIR" ]]; then
    echo "Error: Repository directory not found: ${REPO_DIR}" >&2
    exit 2
  fi
  if [[ ! -d "${REPO_DIR}/.git" ]]; then
    echo "Error: Not a git repository: ${REPO_DIR}" >&2
    exit 2
  fi
  REPO_DIR=$(cd "$REPO_DIR" && pwd)
fi

# ============================================================
# Phase 3: SCHEDULE
# ============================================================
log "Phase 3: Building execution schedule..."

# Set up status tracking
STATUS_DIR=$(mktemp -d)
trap 'rm -rf "$STATUS_DIR"' EXIT

# Resume handling
if [[ -n "$RESUME_ID" ]]; then
  local_report="${DOMAIN_DIR}/run-report.yaml"
  if [[ -f "$local_report" ]]; then
    log "Resuming from: ${RESUME_ID}"
    # Mark previously succeeded tasks
    while IFS= read -r line; do
      if echo "$line" | grep -q '  - id:'; then
        tid=$(echo "$line" | sed 's/.*id: //' | tr -d ' ')
        # Read the next status line
        read -r status_line
        if echo "$status_line" | grep -q 'status: succeeded'; then
          record_task_status "$STATUS_DIR" "$tid" "succeeded"
          log "  Skipping completed: ${tid}"
        fi
      fi
    done < "$local_report"
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

if [[ -z "$REPO_DIR" ]]; then
  echo "Error: --repo is required for execution (use --dry-run to preview without a repo)" >&2
  exit 2
fi

STARTED_AT="$TIMESTAMP"

# Create integration branch
if ! branch_exists "$REPO_DIR" "$INTEGRATION_BRANCH"; then
  create_integration_branch "$REPO_DIR" "$TARGET_BRANCH" "$EXEC_ID" "$DOMAIN" > /dev/null || exit 3
  log "Created integration branch: ${INTEGRATION_BRANCH}"
else
  log "Integration branch exists: ${INTEGRATION_BRANCH}"
fi

# Create task branches
while IFS= read -r tid; do
  status=$(get_task_status "$STATUS_DIR" "$tid")
  if [[ "$status" == "succeeded" ]]; then
    continue
  fi

  task_id_lower=$(echo "$tid" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
  branch_name="agent/${task_id_lower}"

  if ! branch_exists "$REPO_DIR" "$branch_name"; then
    create_task_branch "$REPO_DIR" "$INTEGRATION_BRANCH" "$tid" > /dev/null || exit 3
    log "Created task branch: ${branch_name}"
  fi
done < <(get_all_task_ids "$TASKS_FILE")

# ============================================================
# Phase 5-6: EXECUTE + VERIFY (per phase)
# ============================================================
log "Phase 5-6: Executing tasks..."

while IFS= read -r phase_line; do
  # shellcheck disable=SC2034
  phase_num=""
  parallel=""
  tasks_csv=""
  phase_num=$(echo "$phase_line" | cut -d: -f1)
  parallel=$(echo "$phase_line" | cut -d: -f2)
  tasks_csv=$(echo "$phase_line" | cut -d: -f3)

  log "  Executing phase ${phase_num}..."

  # Process each task in the phase
  for tid in $(echo "$tasks_csv" | tr ',' ' '); do
    current_status=$(get_task_status "$STATUS_DIR" "$tid")

    # Skip already completed or blocked tasks
    if [[ "$current_status" == "succeeded" ]] || [[ "$current_status" == "blocked" ]] || [[ "$current_status" == "skipped" ]]; then
      log "    ${tid}: skipping (${current_status})"
      continue
    fi

    # Check dependencies
    deps=$(get_task_deps "$TASKS_FILE" "$tid")
    if [[ -n "$deps" ]]; then
      if ! check_deps_satisfied "$tid" "$deps" "$STATUS_DIR" 2>/dev/null; then
        record_task_status "$STATUS_DIR" "$tid" "blocked"
        record_task_reason "$STATUS_DIR" "$tid" "Dependency not satisfied"
        mark_dependents_blocked "$TASKS_FILE" "$tid" "$STATUS_DIR"
        log "    ${tid}: blocked (dependency failed)"
        continue
      fi
    fi

    # Execute the task
    record_task_status "$STATUS_DIR" "$tid" "running"
    log "    ${tid}: running..."

    task_name=$(get_task_field "$TASKS_FILE" "$tid" "name")
    complexity=$(get_task_field "$TASKS_FILE" "$tid" "estimated_complexity")
    prompt_context=$(get_prompt_context "$TASKS_FILE" "$tid")  # used by run_task in Model C
    export prompt_context

    task_id_lower=$(echo "$tid" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    branch_name="agent/${task_id_lower}"

    files_list=$(get_files_touched "$TASKS_FILE" "$tid")

    # Run the task (simulate for now — real agents invoked via SKILL.md Model C)
    run_exit=0
    simulate_task_execution "$REPO_DIR" "$tid" "$branch_name" "$files_list" || run_exit=$?

    if [[ "$run_exit" -ne 0 ]]; then
      # Retry logic
      retries=$(get_task_retries "$STATUS_DIR" "$tid")
      retries=$((retries + 1))
      record_task_retries "$STATUS_DIR" "$tid" "$retries"

      if should_retry "$tid" "$retries" "$MAX_ITERATIONS" 2>/dev/null; then
        log "    ${tid}: retrying (${retries}/${MAX_ITERATIONS})"
        continue
      fi

      record_task_status "$STATUS_DIR" "$tid" "failed"
      record_task_reason "$STATUS_DIR" "$tid" "Execution failed after ${retries} retries"
      mark_dependents_blocked "$TASKS_FILE" "$tid" "$STATUS_DIR"
      log "    ${tid}: FAILED"
      continue
    fi

    # Verify file scope
    if ! verify_file_scope "$REPO_DIR" "$INTEGRATION_BRANCH" "$branch_name" "$files_list" 2>/dev/null; then
      record_task_status "$STATUS_DIR" "$tid" "failed"
      record_task_reason "$STATUS_DIR" "$tid" "File scope violation"
      mark_dependents_blocked "$TASKS_FILE" "$tid" "$STATUS_DIR"
      log "    ${tid}: FAILED (scope violation)"
      continue
    fi

    sha=$(get_task_commit_sha "$REPO_DIR" "$branch_name")
    record_task_status "$STATUS_DIR" "$tid" "succeeded"
    record_task_sha "$STATUS_DIR" "$tid" "$sha"
    record_task_retries "$STATUS_DIR" "$tid" "0"
    log "    ${tid}: succeeded"
  done
done < <(get_execution_phases "$TASKS_FILE")

# ============================================================
# Phase 7: MERGE
# ============================================================
log "Phase 7: Merging successful tasks..."

MERGE_ORDER=$(get_merge_order "$TASKS_FILE" | tr '\n' ' ')
MERGED_COUNT=$(merge_tasks_in_order "$REPO_DIR" "$INTEGRATION_BRANCH" "$MERGE_ORDER" "$STATUS_DIR")

log "Merged ${MERGED_COUNT} tasks into ${INTEGRATION_BRANCH}"

# ============================================================
# Phase 8: REPORT
# ============================================================
log "Phase 8: Generating report..."

if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
  FINISHED_AT=$(date -u -d "@${SOURCE_DATE_EPOCH}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u -r "${SOURCE_DATE_EPOCH}" '+%Y-%m-%dT%H:%M:%SZ')
else
  FINISHED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
fi

REPORT_FILE="${DOMAIN_DIR}/run-report.yaml"
generate_run_report "$REPORT_FILE" "$TASKS_FILE" "$STATUS_DIR" \
  "$EXEC_ID" "$DOMAIN" "${REPO_DIR}" "$TARGET_BRANCH" \
  "$INTEGRATION_BRANCH" "$STARTED_AT" "$FINISHED_AT"

# Output summary
echo "Agent Launcher — Execution Complete"
echo "===================================="
echo ""
echo "Domain:             ${DOMAIN}"
echo "Execution ID:       ${EXEC_ID}"
echo "Integration branch: ${INTEGRATION_BRANCH}"
echo "Report:             ${REPORT_FILE}"

print_human_summary "$REPORT_FILE"
