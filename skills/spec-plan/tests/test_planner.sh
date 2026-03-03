#!/usr/bin/env bash
# test_planner.sh — Integration tests for Spec Plan
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLAN_SH="$SKILL_DIR/scripts/plan.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

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

print_summary() {
  local total=$((_PASS + _FAIL + _SKIP))
  echo ""
  echo "--- Results: $total total | ${_PASS} passed | ${_FAIL} failed | ${_SKIP} skipped ---"
  if [[ "$_FAIL" -gt 0 ]]; then
    return 1
  fi
  return 0
}

# ============================================================
# Test 1: Plan frontend-domain fixture — valid tasks.yaml
# ============================================================
test_frontend_valid() {
  local output exit_code=0
  output=$("$BASH" "$PLAN_SH" "$FIXTURES/frontend-domain" --validate-only 2>&1) || exit_code=$?

  assert_exit_code "$exit_code" 0 "T1: frontend-domain validates successfully"
  assert_contains "$output" "Structure:  PASS" "T1: structure check passes"
  assert_contains "$output" "Conflicts:  PASS" "T1: conflict check passes"
  assert_contains "$output" "Coverage:   PASS" "T1: coverage check passes"
}

# ============================================================
# Test 2: Plan backend-domain — schema task has no depends_on
# ============================================================
test_backend_schema_no_deps() {
  local output exit_code=0
  output=$("$BASH" "$PLAN_SH" "$FIXTURES/backend-domain" --validate-only 2>&1) || exit_code=$?

  assert_exit_code "$exit_code" 0 "T2: backend-domain validates successfully"

  # Verify BE-001 (schema task) has empty depends_on
  local tasks_file="$FIXTURES/backend-domain/tasks.yaml"
  # Extract BE-001 depends_on value
  local be001_section
  be001_section=$(sed -n '/- id: BE-001/,/- id: BE-002/p' "$tasks_file" | head -20)
  if echo "$be001_section" | grep -q 'depends_on: \[\]'; then
    _pass "T2: schema task BE-001 has no dependencies"
  else
    _fail "T2: schema task BE-001 has no dependencies" "depends_on is not empty"
  fi
}

# ============================================================
# Test 3: Plan infra-domain — network precedes compute
# ============================================================
test_infra_ordering() {
  local output exit_code=0
  output=$("$BASH" "$PLAN_SH" "$FIXTURES/infra-domain" --validate-only 2>&1) || exit_code=$?

  assert_exit_code "$exit_code" 0 "T3: infra-domain validates successfully"

  # Verify INFRA-003 (compute) depends on INFRA-002 (networking)
  local tasks_file="$FIXTURES/infra-domain/tasks.yaml"
  local infra003_section
  infra003_section=$(sed -n '/- id: INFRA-003/,/- id: INFRA-004/p' "$tasks_file" | head -20)
  if echo "$infra003_section" | grep -q 'INFRA-002'; then
    _pass "T3: compute task depends on networking task"
  else
    _fail "T3: compute task depends on networking task" "INFRA-002 not in INFRA-003 depends_on"
  fi
}

# ============================================================
# Test 4: Parallel safety — no files_touched overlap
# ============================================================
test_parallel_safety() {
  local exit_code=0
  "$BASH" "$PLAN_SH" "$FIXTURES/frontend-domain" --validate-only > /dev/null 2>&1 || exit_code=$?

  assert_exit_code "$exit_code" 0 "T4: no files_touched conflict in parallel phases"

  # Also test with a crafted conflicting tasks.yaml
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf -- "$tmpdir"' RETURN

  # Copy fixture and create a conflict
  cp -r "$FIXTURES/frontend-domain"/* "$tmpdir/"
  # Inject a conflict: make FE-004 also touch a file from FE-003
  sed -i.bak 's|"src/pages/ProductDetail.tsx"|"src/pages/ProductList.tsx"|' "$tmpdir/tasks.yaml" 2>/dev/null \
    || sed -i '' 's|"src/pages/ProductDetail.tsx"|"src/pages/ProductList.tsx"|' "$tmpdir/tasks.yaml"

  local conflict_exit=0
  "$BASH" "$PLAN_SH" "$tmpdir" --validate-only > /dev/null 2>&1 || conflict_exit=$?

  assert_exit_code "$conflict_exit" 3 "T4: detects files_touched conflict (exit code 3)"
}

# ============================================================
# Test 5: AC coverage — all P0 criteria mapped
# ============================================================
test_ac_coverage() {
  local output exit_code=0
  output=$("$BASH" "$PLAN_SH" "$FIXTURES/frontend-domain" --validate-only 2>&1) || exit_code=$?

  # Frontend fixture has all P0 mapped, so should pass
  assert_exit_code "$exit_code" 0 "T5: all P0 acceptance criteria mapped"
  assert_contains "$output" "Coverage:   PASS" "T5: AC coverage check passes"
}

# ============================================================
# Test 6: Missing spec.md — exit code 1
# ============================================================
test_missing_spec() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf -- "$tmpdir"' RETURN

  # Create dir with boundary.yaml but no spec.md
  cp "$FIXTURES/frontend-domain/boundary.yaml" "$tmpdir/"

  local exit_code=0
  local output
  output=$("$BASH" "$PLAN_SH" "$tmpdir" --validate-only 2>&1) || exit_code=$?

  assert_exit_code "$exit_code" 1 "T6: missing spec.md returns exit code 1"
  assert_contains "$output" "spec.md not found" "T6: error message mentions spec.md"
}

# ============================================================
# Test 7: Missing boundary.yaml — exit code 1
# ============================================================
test_missing_boundary() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf -- "$tmpdir"' RETURN

  # Create dir with spec.md but no boundary.yaml
  cp "$FIXTURES/frontend-domain/spec.md" "$tmpdir/"

  local exit_code=0
  local output
  output=$("$BASH" "$PLAN_SH" "$tmpdir" --validate-only 2>&1) || exit_code=$?

  assert_exit_code "$exit_code" 1 "T7: missing boundary.yaml returns exit code 1"
  assert_contains "$output" "boundary.yaml not found" "T7: error message mentions boundary.yaml"
}

# ============================================================
# Test 8: Idempotency — two runs produce identical output
# ============================================================
test_idempotency() {
  local output1 output2

  output1=$("$BASH" "$PLAN_SH" "$FIXTURES/frontend-domain" --validate-only 2>&1) || true
  output2=$("$BASH" "$PLAN_SH" "$FIXTURES/frontend-domain" --validate-only 2>&1) || true

  if [[ "$output1" == "$output2" ]]; then
    _pass "T8: idempotent validation output on two runs"
  else
    _fail "T8: idempotent validation output on two runs" "output differs between runs"
  fi
}

# ============================================================
# Test 9: Empty spec — graceful handling
# ============================================================
test_empty_spec() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf -- "$tmpdir"' RETURN

  # Create a domain with empty spec and minimal boundary
  touch "$tmpdir/spec.md"
  cat > "$tmpdir/boundary.yaml" <<'YAML'
domain: empty
generated_from: test.md
generated_at: "2026-01-01T00:00:00Z"

acceptance_criteria: []
constraints: []
test_hints: []
YAML

  # Create a minimal tasks.yaml with one task
  cat > "$tmpdir/tasks.yaml" <<'YAML'
version: "0.1.0"
domain: "empty"
generated_at: "2026-01-01T00:00:00Z"
generated_from:
  spec: "empty/spec.md"
  boundary: "empty/boundary.yaml"
  contracts: []

tasks:
  - id: EMPTY-001
    name: "Placeholder task"
    depends_on: []
    estimated_complexity: low
    files_touched:
      - "README.md"
    acceptance_criteria: []
    prompt_context: |
      Placeholder for an empty spec.

execution_plan:
  - phase: 1
    tasks:
      - EMPTY-001
    parallel: false
    reason: "Single task"

validation:
  total_tasks: 1
  total_phases: 1
  parallelizable_tasks: 0
  acceptance_criteria_mapped: 0
  acceptance_criteria_unmapped: 0
  unmapped_criteria: []
  files_conflict_check: pass
  spec_coverage: "100%"
YAML

  local exit_code=0
  local output
  output=$("$BASH" "$PLAN_SH" "$tmpdir" --validate-only 2>&1) || exit_code=$?

  assert_exit_code "$exit_code" 0 "T9: empty spec with minimal tasks.yaml validates"
  assert_contains "$output" "Validation PASSED" "T9: validation passes for minimal input"
}

# ============================================================
# Test 10: Custom contracts path
# ============================================================
test_custom_contracts() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf -- "$tmpdir"' RETURN

  # Create a contracts directory
  mkdir -p "$tmpdir/contracts"
  cat > "$tmpdir/contracts/api-contracts.yaml" <<'YAML'
contracts:
  - name: "Product API"
    provider: backend
    consumers: [frontend]
    endpoints:
      - method: GET
        path: /api/v1/products
        description: "List products"
YAML

  local exit_code=0
  local output
  output=$("$BASH" "$PLAN_SH" "$FIXTURES/frontend-domain" --contracts "$tmpdir/contracts" 2>&1) || exit_code=$?

  # Should not error on the contracts path
  if [[ "$exit_code" -le 1 ]]; then
    _pass "T10: custom contracts path accepted"
  else
    _fail "T10: custom contracts path accepted" "exit code $exit_code"
  fi
  assert_contains "$output" "api-contracts.yaml" "T10: contracts file listed in output"
}

# ============================================================
# Bonus: --version and --help flags
# ============================================================
test_version_flag() {
  local output
  output=$("$BASH" "$PLAN_SH" --version 2>&1)
  assert_contains "$output" "spec-plan" "version flag outputs tool name"
  assert_contains "$output" "0.1.0" "version flag outputs version number"
}

test_help_flag() {
  local output
  output=$("$BASH" "$PLAN_SH" --help 2>&1)
  assert_contains "$output" "Usage:" "help flag shows usage"
  assert_contains "$output" "domain_dir" "help flag shows domain_dir argument"
  assert_contains "$output" "--validate-only" "help flag shows --validate-only option"
}

# ============================================================
# Test 11: AC in unmapped_criteria must not count as mapped
# ============================================================
test_unmapped_criteria_not_counted() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf -- "$tmpdir"' RETURN

  # P0 AC exists in boundary but only appears in validation.unmapped_criteria
  cat > "$tmpdir/spec.md" <<'SPEC'
# Test Spec
[EXTRACTED] Placeholder requirement.
SPEC

  cat > "$tmpdir/boundary.yaml" <<'YAML'
domain: test
generated_from: test.md
generated_at: "2026-01-01T00:00:00Z"

acceptance_criteria:
  - id: AC-001
    description: "Critical requirement"
    source_section: "Test"
    priority: P0

constraints: []
test_hints: []
YAML

  cat > "$tmpdir/tasks.yaml" <<'YAML'
version: "0.1.0"
domain: "test"
generated_at: "2026-01-01T00:00:00Z"
generated_from:
  spec: "test/spec.md"
  boundary: "test/boundary.yaml"
  contracts: []

tasks:
  - id: TEST-001
    name: "Placeholder"
    depends_on: []
    estimated_complexity: low
    files_touched:
      - "README.md"
    acceptance_criteria: []
    prompt_context: |
      Do nothing.

execution_plan:
  - phase: 1
    tasks:
      - TEST-001
    parallel: false
    reason: "Single task"

validation:
  total_tasks: 1
  total_phases: 1
  parallelizable_tasks: 0
  acceptance_criteria_mapped: 0
  acceptance_criteria_unmapped: 1
  unmapped_criteria:
    - AC-001
  files_conflict_check: pass
  spec_coverage: "0%"
YAML

  local exit_code=0
  local output
  output=$("$BASH" "$PLAN_SH" "$tmpdir" --validate-only 2>&1) || exit_code=$?

  assert_exit_code "$exit_code" 4 "T11: P0 AC only in unmapped_criteria fails coverage (exit 4)"
  assert_contains "$output" "Coverage:   FAIL" "T11: coverage check reports FAIL"
}

# ============================================================
# Test 12: Phase ordering must respect depends_on
# ============================================================
test_phase_ordering_violation() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf -- "$tmpdir"' RETURN

  cat > "$tmpdir/spec.md" <<'SPEC'
# Test
[EXTRACTED] Placeholder.
SPEC

  cat > "$tmpdir/boundary.yaml" <<'YAML'
domain: test
generated_from: test.md
generated_at: "2026-01-01T00:00:00Z"
acceptance_criteria: []
constraints: []
test_hints: []
YAML

  # TEST-001 in phase 1 depends on TEST-002 in phase 2 — invalid
  cat > "$tmpdir/tasks.yaml" <<'YAML'
version: "0.1.0"
domain: "test"
generated_at: "2026-01-01T00:00:00Z"
generated_from:
  spec: "test/spec.md"
  boundary: "test/boundary.yaml"
  contracts: []

tasks:
  - id: TEST-001
    name: "Runs first but depends on phase 2"
    depends_on:
      - TEST-002
    estimated_complexity: low
    files_touched:
      - "a.ts"
    acceptance_criteria: []
    prompt_context: |
      Depends on TEST-002.

  - id: TEST-002
    name: "Runs second but is a dependency"
    depends_on: []
    estimated_complexity: low
    files_touched:
      - "b.ts"
    acceptance_criteria: []
    prompt_context: |
      Should run first.

execution_plan:
  - phase: 1
    tasks:
      - TEST-001
    parallel: false
    reason: "Wrong order"

  - phase: 2
    tasks:
      - TEST-002
    parallel: false
    reason: "Should be first"

validation:
  total_tasks: 2
  total_phases: 2
  parallelizable_tasks: 0
  acceptance_criteria_mapped: 0
  acceptance_criteria_unmapped: 0
  unmapped_criteria: []
  files_conflict_check: pass
  spec_coverage: "100%"
YAML

  local exit_code=0
  local output
  output=$("$BASH" "$PLAN_SH" "$tmpdir" --validate-only 2>&1) || exit_code=$?

  assert_exit_code "$exit_code" 2 "T12: phase ordering violation returns exit code 2"
  assert_contains "$output" "depends on TEST-002 (phase 2)" "T12: error names the violating dependency"
}

# ============================================================
# Test 13: Task missing from execution plan must fail
# ============================================================
test_task_missing_from_plan() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf -- "$tmpdir"' RETURN

  cat > "$tmpdir/spec.md" <<'SPEC'
# Test
[EXTRACTED] Placeholder.
SPEC

  cat > "$tmpdir/boundary.yaml" <<'YAML'
domain: test
generated_from: test.md
generated_at: "2026-01-01T00:00:00Z"
acceptance_criteria: []
constraints: []
test_hints: []
YAML

  cat > "$tmpdir/tasks.yaml" <<'YAML'
version: "0.1.0"
domain: "test"
generated_at: "2026-01-01T00:00:00Z"
generated_from:
  spec: "test/spec.md"
  boundary: "test/boundary.yaml"
  contracts: []

tasks:
  - id: TEST-001
    name: "In the plan"
    depends_on: []
    estimated_complexity: low
    files_touched:
      - "a.ts"
    acceptance_criteria: []
    prompt_context: |
      Included in execution plan.

  - id: TEST-002
    name: "Missing from plan"
    depends_on: []
    estimated_complexity: low
    files_touched:
      - "b.ts"
    acceptance_criteria: []
    prompt_context: |
      Not in execution plan.

execution_plan:
  - phase: 1
    tasks:
      - TEST-001
    parallel: false
    reason: "Only TEST-001"

validation:
  total_tasks: 2
  total_phases: 1
  parallelizable_tasks: 0
  acceptance_criteria_mapped: 0
  acceptance_criteria_unmapped: 0
  unmapped_criteria: []
  files_conflict_check: pass
  spec_coverage: "100%"
YAML

  local exit_code=0
  local output
  output=$("$BASH" "$PLAN_SH" "$tmpdir" --validate-only 2>&1) || exit_code=$?

  assert_exit_code "$exit_code" 2 "T13: task missing from execution plan returns exit code 2"
  assert_contains "$output" "TEST-002 not found in execution plan" "T13: error names the missing task"
}

# ============================================================
# Run all tests
# ============================================================
echo ">> spec-plan integration tests"
echo ""

test_version_flag
test_help_flag
test_frontend_valid
test_backend_schema_no_deps
test_infra_ordering
test_parallel_safety
test_ac_coverage
test_missing_spec
test_missing_boundary
test_idempotency
test_empty_spec
test_custom_contracts
test_unmapped_criteria_not_counted
test_phase_ordering_violation
test_task_missing_from_plan

print_summary
