#!/usr/bin/env bash
# reporter.sh — Write run-report.yaml and human summary
# Sourced by launch.sh; not intended for standalone execution.

# generate_run_report <output_file> <tasks_yaml> <status_dir> <exec_id> <domain>
#   <target_repo> <base_branch> <integration_branch> <started_at> <finished_at>
# Writes the run-report.yaml file.
generate_run_report() {
  local output_file="$1"
  local tasks_file="$2"
  local status_dir="$3"
  local exec_id="$4"
  local domain="$5"
  local target_repo="$6"
  local base_branch="$7"
  local integration_branch="$8"
  local started_at="$9"
  local finished_at="${10}"

  local succeeded=0 failed=0 blocked=0 skipped=0 total=0

  # Count statuses
  while IFS= read -r tid; do
    total=$((total + 1))
    local status
    status=$(get_task_status "$status_dir" "$tid")
    case "$status" in
      succeeded) succeeded=$((succeeded + 1)) ;;
      failed)    failed=$((failed + 1)) ;;
      blocked)   blocked=$((blocked + 1)) ;;
      skipped)   skipped=$((skipped + 1)) ;;
    esac
  done < <(get_all_task_ids "$tasks_file")

  local pr_ready="false"
  if [[ "$failed" -eq 0 ]] && [[ "$blocked" -eq 0 ]] && [[ "$succeeded" -gt 0 ]]; then
    pr_ready="true"
  fi

  # Write header
  cat > "$output_file" <<YAML
version: "0.1.0"
domain: "${domain}"
execution_id: "${exec_id}"
source_tasks: "${domain}/tasks.yaml"
target_repo: "${target_repo}"
base_branch: "${base_branch}"
integration_branch: "${integration_branch}"
started_at: "${started_at}"
finished_at: "${finished_at}"

tasks:
YAML

  # Write per-task status
  while IFS= read -r tid; do
    local status retries branch_name commit_sha reason
    status=$(get_task_status "$status_dir" "$tid")
    retries=$(get_task_retries "$status_dir" "$tid")

    local tid_lower
    tid_lower=$(echo "$tid" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    branch_name="agent/${tid_lower}"
    commit_sha=""
    reason=""

    if [[ "$status" == "succeeded" ]]; then
      commit_sha=$(cat "${status_dir}/${tid}.sha" 2>/dev/null || echo "")
    fi

    if [[ "$status" == "blocked" ]] || [[ "$status" == "failed" ]]; then
      reason=$(cat "${status_dir}/${tid}.reason" 2>/dev/null || echo "")
    fi

    cat >> "$output_file" <<YAML
  - id: ${tid}
    status: ${status}
    branch: "${branch_name}"
    commit_sha: "${commit_sha}"
    retries: ${retries}
YAML

    if [[ -n "$reason" ]]; then
      cat >> "$output_file" <<YAML
    reason: "${reason}"
YAML
    fi
  done < <(get_all_task_ids "$tasks_file")

  # Write summary
  cat >> "$output_file" <<YAML

summary:
  total_tasks: ${total}
  succeeded: ${succeeded}
  failed: ${failed}
  blocked: ${blocked}
  skipped: ${skipped}
  merged_to_integration_branch: ${succeeded}
  pull_request_ready: ${pr_ready}
YAML
}

# get_task_retries <status_dir> <task_id>
# Returns the retry count for a task. Defaults to 0.
get_task_retries() {
  local status_dir="$1"
  local task_id="$2"

  local retries_file="${status_dir}/${task_id}.retries"
  if [[ -f "$retries_file" ]]; then
    cat "$retries_file"
  else
    echo "0"
  fi
}

# record_task_retries <status_dir> <task_id> <count>
record_task_retries() {
  local status_dir="$1"
  local task_id="$2"
  local count="$3"

  echo "$count" > "${status_dir}/${task_id}.retries"
}

# record_task_sha <status_dir> <task_id> <sha>
record_task_sha() {
  local status_dir="$1"
  local task_id="$2"
  local sha="$3"

  echo "$sha" > "${status_dir}/${task_id}.sha"
}

# record_task_reason <status_dir> <task_id> <reason>
record_task_reason() {
  local status_dir="$1"
  local task_id="$2"
  local reason="$3"

  echo "$reason" > "${status_dir}/${task_id}.reason"
}

# print_human_summary <run_report_file>
# Prints a human-readable summary of the run to stdout.
print_human_summary() {
  local report_file="$1"

  local total succeeded failed blocked skipped
  total=$(grep '  total_tasks:' "$report_file" | awk '{print $2}')
  succeeded=$(grep '  succeeded:' "$report_file" | awk '{print $2}')
  failed=$(grep '  failed:' "$report_file" | head -1 | awk '{print $2}')
  blocked=$(grep '  blocked:' "$report_file" | head -1 | awk '{print $2}')
  skipped=$(grep '  skipped:' "$report_file" | awk '{print $2}')

  local pr_ready
  pr_ready=$(grep '  pull_request_ready:' "$report_file" | awk '{print $2}')

  echo ""
  echo "Execution Summary"
  echo "================="
  echo "  Total:     ${total}"
  echo "  Succeeded: ${succeeded}"
  echo "  Failed:    ${failed}"
  echo "  Blocked:   ${blocked}"
  echo "  Skipped:   ${skipped}"
  echo ""

  if [[ "$pr_ready" == "true" ]]; then
    echo "  PR Ready: YES"
  else
    echo "  PR Ready: NO"
    if [[ "${failed:-0}" -gt 0 ]]; then
      echo ""
      echo "  Failed tasks require attention:"
      grep -A2 'status: failed' "$report_file" | grep 'id:' | while IFS= read -r line; do
        local tid
        tid="${line##*id: }"
        echo "    - ${tid}"
      done
    fi
  fi
}
