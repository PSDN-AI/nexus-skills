#!/usr/bin/env bash
# test_decompose.sh — Integration tests for PRD Decomposer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DECOMPOSE="$SKILL_DIR/scripts/decompose.sh"
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

assert_not_contains() {
  local haystack="$1" needle="$2" description="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    _fail "$description" "expected NOT to find: $needle"
  else
    _pass "$description"
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

assert_dir_exists() {
  local dirpath="$1" description="$2"
  if [[ -d "$dirpath" ]]; then
    _pass "$description"
  else
    _fail "$description" "directory not found: $dirpath"
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
# Test: --version flag
# ============================================================
test_version_flag() {
  local output
  output=$("$BASH" "$DECOMPOSE" --version 2>&1)
  assert_contains "$output" "prd-decomposer" "version flag outputs tool name"
  assert_contains "$output" "0.1.0" "version flag outputs version number"
}

# ============================================================
# Test: --help flag
# ============================================================
test_help_flag() {
  local output
  output=$("$BASH" "$DECOMPOSE" --help 2>&1)
  assert_contains "$output" "Usage:" "help flag shows usage"
  assert_contains "$output" "prd_path" "help flag shows prd_path argument"
  assert_contains "$output" "--output" "help flag shows --output option"
  assert_contains "$output" "--dry-run" "help flag shows --dry-run option"
}

# ============================================================
# Test: Missing PRD file
# ============================================================
test_missing_prd_file() {
  local exit_code=0
  "$BASH" "$DECOMPOSE" /nonexistent/file.md > /dev/null 2>&1 || exit_code=$?
  assert_exit_code "$exit_code" 1 "missing PRD file returns exit code 1"
}

# ============================================================
# Test: No arguments
# ============================================================
test_no_arguments() {
  local exit_code=0
  "$BASH" "$DECOMPOSE" > /dev/null 2>&1 || exit_code=$?
  assert_exit_code "$exit_code" 1 "no arguments returns exit code 1"
}

# ============================================================
# Test: Simple PRD decomposition
# ============================================================
test_simple_prd() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  local output
  output=$("$BASH" "$DECOMPOSE" "$FIXTURES/sample-prd-simple.md" --output "$tmpdir/output" 2>&1)

  assert_contains "$output" "PRD Decomposition Complete" "simple PRD reports completion"
  assert_contains "$output" "frontend/" "simple PRD identifies frontend domain"
  assert_contains "$output" "backend/" "simple PRD identifies backend domain"

  assert_dir_exists "$tmpdir/output/frontend" "simple PRD creates frontend dir"
  assert_dir_exists "$tmpdir/output/backend" "simple PRD creates backend dir"

  assert_file_exists "$tmpdir/output/frontend/spec.md" "simple PRD creates frontend spec"
  assert_file_exists "$tmpdir/output/frontend/boundary.yaml" "simple PRD creates frontend boundary"
  assert_file_exists "$tmpdir/output/frontend/config.yaml" "simple PRD creates frontend config"

  assert_file_exists "$tmpdir/output/backend/spec.md" "simple PRD creates backend spec"
  assert_file_exists "$tmpdir/output/backend/boundary.yaml" "simple PRD creates backend boundary"
  assert_file_exists "$tmpdir/output/backend/config.yaml" "simple PRD creates backend config"

  assert_file_exists "$tmpdir/output/meta.yaml" "simple PRD creates meta.yaml"
  assert_dir_exists "$tmpdir/output/contracts" "simple PRD creates contracts dir"

  # Verify meta.yaml content
  local meta
  meta=$(cat "$tmpdir/output/meta.yaml")
  assert_contains "$meta" "generator: \"prd-decomposer@0.1.0\"" "meta.yaml has generator field"
  assert_contains "$meta" "prd_source:" "meta.yaml has prd_source field"
}

# ============================================================
# Test: Complex PRD decomposition
# ============================================================
test_complex_prd() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  local output
  output=$("$BASH" "$DECOMPOSE" "$FIXTURES/sample-prd-complex.md" --output "$tmpdir/output" 2>&1)

  assert_contains "$output" "PRD Decomposition Complete" "complex PRD reports completion"
  assert_contains "$output" "frontend/" "complex PRD identifies frontend"
  assert_contains "$output" "backend/" "complex PRD identifies backend"
  assert_contains "$output" "infra/" "complex PRD identifies infra"
  assert_contains "$output" "security/" "complex PRD identifies security"

  # Should find API contracts
  assert_file_exists "$tmpdir/output/contracts/api-contracts.yaml" "complex PRD creates API contracts"
  local api_contracts
  api_contracts=$(cat "$tmpdir/output/contracts/api-contracts.yaml")
  assert_contains "$api_contracts" "/api/v1/users" "API contracts contain user endpoint"

  # Verify dependency graph
  assert_file_exists "$tmpdir/output/contracts/dependency-graph.md" "complex PRD creates dependency graph"
}

# ============================================================
# Test: Minimal PRD (no headings)
# ============================================================
test_minimal_prd() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  local output
  output=$("$BASH" "$DECOMPOSE" "$FIXTURES/sample-prd-minimal.md" --output "$tmpdir/output" 2>&1)

  assert_contains "$output" "PRD Decomposition Complete" "minimal PRD reports completion"
  assert_file_exists "$tmpdir/output/meta.yaml" "minimal PRD creates meta.yaml"

  # With no headings, parser treats entire doc as one "Untitled" section.
  # Content has keywords ("database", "form") so it gets classified.
  local meta
  meta=$(cat "$tmpdir/output/meta.yaml")
  assert_contains "$meta" "total_sections: 1" "minimal PRD has 1 section"
}

# ============================================================
# Test: Dry run mode
# ============================================================
test_dry_run() {
  local output
  output=$("$BASH" "$DECOMPOSE" "$FIXTURES/sample-prd-simple.md" --dry-run 2>&1)

  assert_contains "$output" "Dry Run" "dry run shows mode indicator"
  assert_contains "$output" "Section Classification Detail" "dry run shows classification detail"
  assert_contains "$output" "frontend" "dry run shows frontend domain"
  assert_contains "$output" "backend" "dry run shows backend domain"

  # Dry run should NOT create output files
  assert_not_contains "$output" "PRD Decomposition Complete" "dry run does not report completion"
}

# ============================================================
# Test: Idempotency
# ============================================================
test_idempotency() {
  local tmpdir1 tmpdir2
  tmpdir1=$(mktemp -d)
  tmpdir2=$(mktemp -d)
  trap "rm -rf '$tmpdir1' '$tmpdir2'" RETURN

  "$BASH" "$DECOMPOSE" "$FIXTURES/sample-prd-simple.md" --output "$tmpdir1/output" > /dev/null 2>&1
  "$BASH" "$DECOMPOSE" "$FIXTURES/sample-prd-simple.md" --output "$tmpdir2/output" > /dev/null 2>&1

  # Compare directory structures (file names only, not timestamps)
  local files1 files2
  files1=$(cd "$tmpdir1/output" && find . -type f | sort)
  files2=$(cd "$tmpdir2/output" && find . -type f | sort)

  if [[ "$files1" == "$files2" ]]; then
    _pass "idempotency: same file structure on two runs"
  else
    _fail "idempotency: different file structures" "run1: $files1 | run2: $files2"
  fi
}

# ============================================================
# Test: Spec content has [EXTRACTED] markers
# ============================================================
test_extracted_markers() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  "$BASH" "$DECOMPOSE" "$FIXTURES/sample-prd-simple.md" --output "$tmpdir/output" > /dev/null 2>&1

  local spec
  spec=$(cat "$tmpdir/output/frontend/spec.md")
  assert_contains "$spec" "[EXTRACTED]" "spec contains [EXTRACTED] markers"
  assert_contains "$spec" "[GENERATED]" "spec contains [GENERATED] markers"
}

# ============================================================
# Test: Config.yaml has required fields
# ============================================================
test_config_fields() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  "$BASH" "$DECOMPOSE" "$FIXTURES/sample-prd-simple.md" --output "$tmpdir/output" > /dev/null 2>&1

  local config
  config=$(cat "$tmpdir/output/frontend/config.yaml")
  assert_contains "$config" "domain:" "config has domain field"
  assert_contains "$config" "target_repo:" "config has target_repo field"
  assert_contains "$config" "review_required: true" "config has review_required field"
}

# ============================================================
# Test: Boundary.yaml has acceptance criteria
# ============================================================
test_boundary_acceptance_criteria() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" RETURN

  "$BASH" "$DECOMPOSE" "$FIXTURES/sample-prd-complex.md" --output "$tmpdir/output" > /dev/null 2>&1

  local boundary
  boundary=$(cat "$tmpdir/output/frontend/boundary.yaml")
  assert_contains "$boundary" "acceptance_criteria:" "boundary has acceptance_criteria section"
  assert_contains "$boundary" "test_hints:" "boundary has test_hints section"
}

# ============================================================
# Run all tests
# ============================================================
echo ">> prd-decomposer integration tests"
echo ""

test_version_flag
test_help_flag
test_missing_prd_file
test_no_arguments
test_simple_prd
test_complex_prd
test_minimal_prd
test_dry_run
test_idempotency
test_extracted_markers
test_config_fields
test_boundary_acceptance_criteria

print_summary
