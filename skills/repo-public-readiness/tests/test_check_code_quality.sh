#!/usr/bin/env bash
# test_check_code_quality.sh — Tests for check_code_quality.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANNER_DIR="${1:?Usage: test_check_code_quality.sh <scanner_dir>}"

# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

CHECK="$SCANNER_DIR/check_code_quality.sh"

# ============================================================
# TODO / FIXME / HACK detection
# ============================================================

test_todo_detected() {
  setup_fixture_dir
  create_file_ln "app.py" "# TODO: fix this later
def main():
    pass"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "LOW|todo_comment" "detects TODO comment"
  teardown_fixture_dir
}

test_fixme_detected() {
  setup_fixture_dir
  create_file_ln "app.js" "// FIXME: broken logic
function main() {}"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "LOW|todo_comment" "detects FIXME comment"
  teardown_fixture_dir
}

test_hack_detected() {
  setup_fixture_dir
  create_file_ln "main.go" "// HACK: workaround for API bug
package main"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "LOW|todo_comment" "detects HACK comment"
  teardown_fixture_dir
}

test_scanner_dir_excluded() {
  setup_fixture_dir
  # check_code_quality.sh excludes paths matching /repo-public-readiness/scanner/
  mkdir -p "$FIXTURE_REPO/repo-public-readiness/scanner"
  create_file_ln "repo-public-readiness/scanner/check.sh" "# TODO: this should be excluded"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "todo_comment" "scanner dir excluded from TODO scan"
  teardown_fixture_dir
}

test_no_todos_clean() {
  setup_fixture_dir
  create_file_ln "app.py" "def main():
    print('hello')
    return 0"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "todo_comment" "clean code has no TODO findings"
  teardown_fixture_dir
}

# ============================================================
# Optional tool handling
# ============================================================

test_npm_audit_skipped_no_package_json() {
  setup_fixture_dir
  # No package.json — npm audit should not appear at all
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "npm_audit" "no npm_audit without package.json"
  teardown_fixture_dir
}

test_shellcheck_handling() {
  setup_fixture_dir
  create_file_ln "test.sh" "#!/bin/bash
echo hello"
  run_check "$CHECK"
  if command -v shellcheck &>/dev/null && command -v jq &>/dev/null; then
    assert_not_contains "$OUTPUT" "SKIPPED|shellcheck" "shellcheck runs when installed"
  elif command -v shellcheck &>/dev/null; then
    assert_contains "$OUTPUT" "SKIPPED|shellcheck_jq" "shellcheck SKIPPED (jq missing)"
  else
    assert_contains "$OUTPUT" "SKIPPED|shellcheck" "shellcheck SKIPPED when not installed"
  fi
  teardown_fixture_dir
}

test_trivy_handling() {
  setup_fixture_dir
  run_check "$CHECK"
  if command -v trivy &>/dev/null && command -v jq &>/dev/null; then
    assert_not_contains "$OUTPUT" "SKIPPED|trivy" "trivy runs when installed"
  else
    assert_contains "$OUTPUT" "SKIPPED|trivy" "trivy SKIPPED when not installed"
  fi
  teardown_fixture_dir
}

# ============================================================
# Run all tests
# ============================================================

echo ">> check_code_quality.sh"
test_todo_detected
test_fixme_detected
test_hack_detected
test_scanner_dir_excluded
test_no_todos_clean
test_npm_audit_skipped_no_package_json
test_shellcheck_handling
test_trivy_handling
print_summary
