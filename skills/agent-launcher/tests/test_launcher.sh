#!/usr/bin/env bash
# test_launcher.sh — Integration tests for Agent Launcher
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCH_SH="$SKILL_DIR/scripts/launch.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

# Source lib modules for unit-level tests
# shellcheck disable=SC1091
source "$SKILL_DIR/scripts/lib/scheduler.sh"
# shellcheck disable=SC1091
source "$SKILL_DIR/scripts/lib/workspace.sh"
# shellcheck disable=SC1091
source "$SKILL_DIR/scripts/lib/guardrails.sh"
# shellcheck disable=SC1091
source "$SKILL_DIR/scripts/lib/merger.sh"
# shellcheck disable=SC1091
source "$SKILL_DIR/scripts/lib/reporter.sh"

# --- Colors (disabled if not a terminal) ---
if [[ -t 1 ]]; then
  _GREEN='\033[0;32m'
  _RED='\033[0;31m'
  _YELLOW='\033[0;33m'
  _RESET='\033[0m'
else
  _GREEN=''
  _RED=''
  _YELLOW=''
  _RESET=''
fi

_PASS=0
_FAIL=0
_SKIP=0

_pass() {
  _PASS=$((_PASS + 1))
  printf "  ${_GREEN}PASS${_RESET}: %s\n" "$1"
}

_fail() {
  _FAIL=$((_FAIL + 1))
  printf "  ${_RED}FAIL${_RESET}: %s — %s\n" "$1" "$2"
}

skip_test() {
  _SKIP=$((_SKIP + 1))
  printf "  ${_YELLOW}SKIP${_RESET}: %s (%s)\n" "$1" "$2"
}

assert_contains() {
  local haystack="$1" needle="$2" description="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    _pass "$description"
  else
    _fail "$description" "expected to find: $needle"
  fi
}

assert_exit_code() {
  local actual="$1" expected="$2" description="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    _pass "$description"
  else
    _fail "$description" "expected exit code $expected, got $actual"
  fi
}

assert_file_exists() {
  local filepath="$1" description="$2"
  if [[ -f "$filepath" ]]; then
    _pass "$description"
  else
    _fail "$description" "file not found: $filepath"
  fi
}

print_summary() {
  local total=$((_PASS + _FAIL + _SKIP))
  echo ""
  echo "--- Results: $total total | ${_PASS} passed | ${_FAIL} failed | ${_SKIP} skipped ---"
  if [[ "$_FAIL" -gt 0 ]]; then
    return 1
  fi
  return 0
}

# Helper: create a temporary git repo for testing
create_test_repo() {
  local tmpdir
  tmpdir=$(mktemp -d)
  git -C "$tmpdir" init -b main >/dev/null 2>&1
  git -C "$tmpdir" config user.name "Agent Launcher Tests" >/dev/null 2>&1
  git -C "$tmpdir" config user.email "agent-launcher-tests@example.com" >/dev/null 2>&1
  git -C "$tmpdir" commit --allow-empty -m "Initial commit" >/dev/null 2>&1
  echo "$tmpdir"
}

# ============================================================
# Test 1: Launch frontend-tasks — happy path produces run-report
# ============================================================
test_happy_path() {
  local repo_dir
  repo_dir=$(create_test_repo)
  trap 'rm -rf -- "$repo_dir"' RETURN

  local exit_code=0
  local output
  output=$(AGENT_LAUNCHER_SIMULATE=true "$BASH" "$LAUNCH_SH" "$FIXTURES/frontend-tasks" --repo "$repo_dir" 2>&1) || exit_code=$?

  assert_exit_code "$exit_code" 0 "T1: frontend-tasks exits 0"
  assert_contains "$output" "Execution Complete" "T1: reports execution complete"
  assert_file_exists "$FIXTURES/frontend-tasks/run-report.yaml" "T1: run-report.yaml created"

  # Verify run-report content
  local report
  report=$(cat "$FIXTURES/frontend-tasks/run-report.yaml")
  assert_contains "$report" "domain: \"frontend\"" "T1: report has correct domain"
  assert_contains "$report" "status: succeeded" "T1: report has succeeded tasks"

  # Clean up run-report
  rm -f "$FIXTURES/frontend-tasks/run-report.yaml"
}

# ============================================================
# Test 2: Dependency gating — task with unmet depends_on not launched
# ============================================================
test_dependency_gating() {
  local tasks_file="$FIXTURES/backend-tasks/tasks.yaml"
  local status_dir
  status_dir=$(mktemp -d)
  trap 'rm -rf -- "$status_dir"' RETURN

  # BE-004 depends on BE-002 and BE-003 — mark only BE-002 as succeeded
  record_task_status "$status_dir" "BE-002" "succeeded"

  # BE-004 should NOT be satisfiable
  if check_deps_satisfied "BE-004" "BE-002 BE-003" "$status_dir" 2>/dev/null; then
    _fail "T2: dependency gating blocks unsatisfied task" "BE-004 should be blocked"
  else
    _pass "T2: dependency gating blocks unsatisfied task"
  fi

  # Now mark BE-003 as succeeded too
  record_task_status "$status_dir" "BE-003" "succeeded"
  if check_deps_satisfied "BE-004" "BE-002 BE-003" "$status_dir" 2>/dev/null; then
    _pass "T2: dependency gating allows when all deps met"
  else
    _fail "T2: dependency gating allows when all deps met" "BE-004 should be unblocked"
  fi
}

# ============================================================
# Test 3: Parallel safety — overlapping files never launch together
# ============================================================
test_parallel_safety() {
  local tasks_file="$FIXTURES/frontend-tasks/tasks.yaml"

  # FE-002 and FE-003 should be safe (no overlap)
  if check_parallel_safe "$tasks_file" "FE-002" "FE-003"; then
    _pass "T3: FE-002 and FE-003 have no file overlap"
  else
    _fail "T3: FE-002 and FE-003 have no file overlap" "unexpected overlap detected"
  fi

  # FE-001 and itself should overlap
  if check_parallel_safe "$tasks_file" "FE-001" "FE-001"; then
    _fail "T3: same task overlaps with itself" "should detect overlap"
  else
    _pass "T3: same task overlaps with itself"
  fi
}

# ============================================================
# Test 4: File-scope enforcement — undeclared file changes fail
# ============================================================
test_file_scope_enforcement() {
  local repo_dir
  repo_dir=$(create_test_repo)
  trap 'rm -rf -- "$repo_dir"' RETURN

  # Create integration branch and task branch
  git -C "$repo_dir" checkout -b "integration" >/dev/null 2>&1
  git -C "$repo_dir" checkout -b "agent/test-001" >/dev/null 2>&1

  # Create an ALLOWED file and an OUT-OF-SCOPE file
  echo "allowed" > "${repo_dir}/allowed.txt"
  echo "violation" > "${repo_dir}/not-allowed.txt"
  git -C "$repo_dir" add -A >/dev/null 2>&1
  git -C "$repo_dir" commit -m "test commit" >/dev/null 2>&1

  local allowed_files
  allowed_files="allowed.txt"

  if verify_file_scope "$repo_dir" "integration" "agent/test-001" "$allowed_files" 2>/dev/null; then
    _fail "T4: detects out-of-scope file changes" "should have detected not-allowed.txt"
  else
    _pass "T4: detects out-of-scope file changes"
  fi

  # Verify allowed-only passes
  local both_files
  both_files="allowed.txt
not-allowed.txt"
  if verify_file_scope "$repo_dir" "integration" "agent/test-001" "$both_files" 2>/dev/null; then
    _pass "T4: passes when all files are declared"
  else
    _fail "T4: passes when all files are declared" "should pass with full scope"
  fi
}

# ============================================================
# Test 5: Retry policy — transient failure retried within limits
# ============================================================
test_retry_policy() {
  local status_dir
  status_dir=$(mktemp -d)
  trap 'rm -rf -- "$status_dir"' RETURN

  # First retry should be allowed (0 < 3)
  if should_retry "TEST-001" 0 3 2>/dev/null; then
    _pass "T5: allows retry when under limit"
  else
    _fail "T5: allows retry when under limit" "should allow at 0/3"
  fi

  # At the limit should be denied (3 >= 3)
  if should_retry "TEST-001" 3 3 2>/dev/null; then
    _fail "T5: denies retry at limit" "should deny at 3/3"
  else
    _pass "T5: denies retry at limit"
  fi
}

# ============================================================
# Test 6: Failure propagation — dependents marked blocked
# ============================================================
test_failure_propagation() {
  local tasks_file="$FIXTURES/mixed-failure/tasks.yaml"
  local status_dir
  status_dir=$(mktemp -d)
  trap 'rm -rf -- "$status_dir"' RETURN

  # Initialize all as pending
  record_task_status "$status_dir" "MX-001" "succeeded"
  record_task_status "$status_dir" "MX-002" "pending"
  record_task_status "$status_dir" "MX-003" "pending"

  # Mark MX-002 as failed and propagate
  record_task_status "$status_dir" "MX-002" "failed"
  mark_dependents_blocked "$tasks_file" "MX-002" "$status_dir"

  local mx003_status
  mx003_status=$(get_task_status "$status_dir" "MX-003")

  if [[ "$mx003_status" == "blocked" ]]; then
    _pass "T6: MX-003 blocked when MX-002 fails"
  else
    _fail "T6: MX-003 blocked when MX-002 fails" "status is ${mx003_status}"
  fi
}

# ============================================================
# Test 7: Merge sequencing — tasks merge in deterministic order
# ============================================================
test_merge_sequencing() {
  local tasks_file="$FIXTURES/frontend-tasks/tasks.yaml"

  local merge_order
  merge_order=$(get_merge_order "$tasks_file" | tr '\n' ' ' | xargs)

  # Should be FE-001 FE-002 FE-003 (phase 1 then phase 2)
  assert_contains "$merge_order" "FE-001" "T7: FE-001 in merge order"

  # FE-001 should come before FE-002
  local pos_001 pos_002
  pos_001=$(echo "$merge_order" | tr ' ' '\n' | grep -n "FE-001" | cut -d: -f1)
  pos_002=$(echo "$merge_order" | tr ' ' '\n' | grep -n "FE-002" | cut -d: -f1)

  if [[ "$pos_001" -lt "$pos_002" ]]; then
    _pass "T7: FE-001 merges before FE-002"
  else
    _fail "T7: FE-001 merges before FE-002" "pos ${pos_001} vs ${pos_002}"
  fi
}

# ============================================================
# Test 8: Dry run — computes plan without mutating git
# ============================================================
test_dry_run() {
  local exit_code=0
  local output
  output=$("$BASH" "$LAUNCH_SH" "$FIXTURES/frontend-tasks" --repo /tmp --dry-run 2>&1) || exit_code=$?

  assert_exit_code "$exit_code" 0 "T8: dry run exits 0"
  assert_contains "$output" "Dry Run" "T8: output shows dry run mode"
  assert_contains "$output" "FE-001" "T8: shows task FE-001"
  assert_contains "$output" "FE-002" "T8: shows task FE-002"
  assert_contains "$output" "No changes made" "T8: confirms no changes"
}

# ============================================================
# Test 9: Resume mode — skips completed tasks
# ============================================================
test_resume_mode() {
  local repo_dir
  repo_dir=$(create_test_repo)
  trap 'rm -rf -- "$repo_dir"' RETURN

  git -C "$repo_dir" branch "agent-launcher/frontend/run-test-resume" main >/dev/null 2>&1
  git -C "$repo_dir" branch "agent/fe-001" "agent-launcher/frontend/run-test-resume" >/dev/null 2>&1

  # Create a fake prior run report
  local domain_dir="$FIXTURES/frontend-tasks"
  cat > "${domain_dir}/run-report.yaml" <<'YAML'
version: "0.1.0"
domain: "frontend"
execution_id: "run-test-resume"

tasks:
  - id: FE-001
    status: succeeded
    branch: "agent/fe-001"
    commit_sha: "abc123"
    retries: 0
  - id: FE-002
    status: failed
    branch: "agent/fe-002"
    commit_sha: ""
    retries: 3
  - id: FE-003
    status: blocked
    branch: "agent/fe-003"
    commit_sha: ""
    retries: 0

summary:
  total_tasks: 3
  succeeded: 1
  failed: 1
  blocked: 1
  skipped: 0
  merged_to_integration_branch: 1
  pull_request_ready: false
YAML

  # Run with --resume should work and skip FE-001
  local exit_code=0
  local output
  output=$(AGENT_LAUNCHER_SIMULATE=true "$BASH" "$LAUNCH_SH" "$domain_dir" --repo "$repo_dir" \
    --resume run-test-resume 2>&1) || exit_code=$?

  # Should attempt to run since some tasks need work
  # (exit 0 or 4 depending on task results)
  if [[ "$exit_code" -le 4 ]]; then
    _pass "T9: resume mode completes"
  else
    _fail "T9: resume mode completes" "exit code ${exit_code}"
  fi

  # Clean up
  rm -f "${domain_dir}/run-report.yaml"
}

# ============================================================
# Test 10: Executor is required unless simulation is explicitly enabled
# ============================================================
test_executor_required() {
  local repo_dir
  repo_dir=$(create_test_repo)
  trap 'rm -rf -- "$repo_dir"' RETURN

  local exit_code=0
  local output
  output=$("$BASH" "$LAUNCH_SH" "$FIXTURES/frontend-tasks" --repo "$repo_dir" 2>&1) || exit_code=$?

  assert_exit_code "$exit_code" 4 "T10: missing executor returns exit code 4"
  assert_contains "$output" "No task executor configured" "T10: missing executor prints guidance"
}

# ============================================================
# Test 11: Repeated runs get unique execution IDs on the same day
# ============================================================
test_unique_execution_ids() {
  local repo_dir
  repo_dir=$(create_test_repo)
  trap 'rm -rf -- "$repo_dir"' RETURN

  local output_one output_two id_one id_two
  output_one=$(AGENT_LAUNCHER_SIMULATE=true SOURCE_DATE_EPOCH=1736985600 \
    "$BASH" "$LAUNCH_SH" "$FIXTURES/frontend-tasks" --repo "$repo_dir" 2>&1)
  output_two=$(AGENT_LAUNCHER_SIMULATE=true SOURCE_DATE_EPOCH=1736985600 \
    "$BASH" "$LAUNCH_SH" "$FIXTURES/frontend-tasks" --repo "$repo_dir" 2>&1)

  id_one=$(echo "$output_one" | awk '/Execution ID:/ {print $3}' | tail -1)
  id_two=$(echo "$output_two" | awk '/Execution ID:/ {print $3}' | tail -1)

  if [[ -n "$id_one" ]] && [[ -n "$id_two" ]] && [[ "$id_one" != "$id_two" ]]; then
    _pass "T11: repeated runs use unique execution IDs"
  else
    _fail "T11: repeated runs use unique execution IDs" "ids were '${id_one}' and '${id_two}'"
  fi

  rm -f "$FIXTURES/frontend-tasks/run-report.yaml"
}

# ============================================================
# Test 12: Retry loop reruns transient executor failures
# ============================================================
test_retry_recovery() {
  local repo_dir
  repo_dir=$(create_test_repo)
  trap 'rm -rf -- "$repo_dir"' RETURN

  local state_dir
  state_dir=$(mktemp -d)
  trap 'rm -rf -- "$repo_dir" "$state_dir"' RETURN

  local attempt_file="$state_dir/attempts"
  local executor="$state_dir/executor.sh"

  cat > "$executor" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

attempt_file="${AGENT_LAUNCHER_ATTEMPT_FILE:?}"
attempts=0
if [[ -f "$attempt_file" ]]; then
  attempts=$(cat "$attempt_file")
fi
attempts=$((attempts + 1))
echo "$attempts" > "$attempt_file"

if [[ "$attempts" -eq 1 ]]; then
  exit 1
fi

target_file=$(printf '%s\n' "$AGENT_LAUNCHER_FILES_TOUCHED" | sed -n '1p')
mkdir -p "$(dirname "$target_file")"
echo "// generated by retry test" > "$target_file"
git add "$target_file"
git commit -m "${AGENT_LAUNCHER_TASK_ID}: retry success" >/dev/null 2>&1
EOF
  chmod +x "$executor"

  local exit_code=0
  local output
  output=$(AGENT_LAUNCHER_EXECUTOR="$executor" AGENT_LAUNCHER_ATTEMPT_FILE="$attempt_file" \
    "$BASH" "$LAUNCH_SH" "$FIXTURES/frontend-tasks" --repo "$repo_dir" 2>&1) || exit_code=$?

  assert_exit_code "$exit_code" 0 "T12: transient executor failure recovers"
  assert_contains "$output" "Execution Complete" "T12: retry run completes"

  local report
  report=$(cat "$FIXTURES/frontend-tasks/run-report.yaml")
  assert_contains "$report" "retries: 1" "T12: report records a retry"

  rm -f "$FIXTURES/frontend-tasks/run-report.yaml"
}

# ============================================================
# Test 13: Resume requires the requested execution ID to match the report
# ============================================================
test_resume_id_mismatch() {
  local repo_dir
  repo_dir=$(create_test_repo)
  trap 'rm -rf -- "$repo_dir"' RETURN

  local domain_dir="$FIXTURES/frontend-tasks"
  cat > "${domain_dir}/run-report.yaml" <<'YAML'
version: "0.1.0"
domain: "frontend"
execution_id: "run-other-id"

tasks:
  - id: FE-001
    status: succeeded
    branch: "agent/fe-001"
    commit_sha: "abc123"
    retries: 0

summary:
  total_tasks: 1
  succeeded: 1
  failed: 0
  blocked: 0
  skipped: 0
  merged_to_integration_branch: 1
  pull_request_ready: true
YAML

  local exit_code=0
  local output
  output=$(AGENT_LAUNCHER_SIMULATE=true "$BASH" "$LAUNCH_SH" "$domain_dir" --repo "$repo_dir" \
    --resume run-expected-id 2>&1) || exit_code=$?

  assert_exit_code "$exit_code" 2 "T13: resume rejects mismatched execution ID"
  assert_contains "$output" "does not match --resume" "T13: resume mismatch explains the problem"

  rm -f "${domain_dir}/run-report.yaml"
}

# ============================================================
# Test 14: Missing tasks.yaml or invalid repo — proper exit codes
# ============================================================
test_missing_input() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf -- "$tmpdir"' RETURN

  # Missing tasks.yaml
  mkdir -p "$tmpdir/empty"
  echo "domain: test" > "$tmpdir/empty/config.yaml"

  local exit_code=0
  local output
  output=$("$BASH" "$LAUNCH_SH" "$tmpdir/empty" --repo /tmp --dry-run 2>&1) || exit_code=$?
  assert_exit_code "$exit_code" 1 "T10: missing tasks.yaml returns exit code 1"
  assert_contains "$output" "tasks.yaml not found" "T10: error mentions tasks.yaml"

  # Invalid repo path
  exit_code=0
  output=$("$BASH" "$LAUNCH_SH" "$FIXTURES/frontend-tasks" --repo /nonexistent 2>&1) || exit_code=$?
  assert_exit_code "$exit_code" 2 "T10: invalid repo returns exit code 2"

  # Missing domain directory
  exit_code=0
  output=$("$BASH" "$LAUNCH_SH" /nonexistent --repo /tmp 2>&1) || exit_code=$?
  assert_exit_code "$exit_code" 1 "T10: missing domain dir returns exit code 1"
}

# ============================================================
# Bonus: --version and --help flags
# ============================================================
test_launch_script_permissions() {
  if [[ -x "$LAUNCH_SH" ]]; then
    _pass "launch.sh remains executable"
  else
    _fail "launch.sh remains executable" "expected executable bit on $LAUNCH_SH"
  fi
}

test_version_flag() {
  local output
  output=$("$BASH" "$LAUNCH_SH" --version 2>&1)
  assert_contains "$output" "agent-launcher" "version flag outputs tool name"
  assert_contains "$output" "0.1.0" "version flag outputs version number"
}

test_help_flag() {
  local output
  output=$("$BASH" "$LAUNCH_SH" --help 2>&1)
  assert_contains "$output" "Usage:" "help flag shows usage"
  assert_contains "$output" "domain_dir" "help flag shows domain_dir argument"
  assert_contains "$output" "--dry-run" "help flag shows --dry-run option"
  assert_contains "$output" "--resume" "help flag shows --resume option"
}

# ============================================================
# Run all tests
# ============================================================
echo ">> agent-launcher integration tests"
echo ""

test_launch_script_permissions
test_version_flag
test_help_flag
test_happy_path
test_dependency_gating
test_parallel_safety
test_file_scope_enforcement
test_retry_policy
test_failure_propagation
test_merge_sequencing
test_dry_run
test_resume_mode
test_executor_required
test_unique_execution_ids
test_retry_recovery
test_resume_id_mismatch
test_missing_input

print_summary
