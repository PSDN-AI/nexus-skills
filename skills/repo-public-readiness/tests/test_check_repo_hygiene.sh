#!/usr/bin/env bash
# test_check_repo_hygiene.sh — Tests for check_repo_hygiene.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANNER_DIR="${1:?Usage: test_check_repo_hygiene.sh <scanner_dir>}"

# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

CHECK="$SCANNER_DIR/check_repo_hygiene.sh"

# ============================================================
# Large file tests
# ============================================================

test_large_file_detected() {
  setup_fixture_dir
  create_file_of_size "big.bin" 12
  run_check "$CHECK"
  assert_contains "$OUTPUT" "MEDIUM|large_file" "detects file >10MB"
  teardown_fixture_dir
}

test_small_file_not_flagged() {
  setup_fixture_dir
  create_file_of_size "small.bin" 1
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "large_file" "file <10MB not flagged"
  teardown_fixture_dir
}

# ============================================================
# Log file tests
# ============================================================

test_log_file_detected() {
  setup_fixture_dir
  create_file "app.log" "some log output"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "MEDIUM|log_file" "detects .log file"
  teardown_fixture_dir
}

# ============================================================
# Data dump tests
# ============================================================

test_data_dump_detected() {
  setup_fixture_dir
  create_file_of_size "backup.sql" 2
  run_check "$CHECK"
  assert_contains "$OUTPUT" "HIGH|data_dump" "detects SQL dump >1MB"
  teardown_fixture_dir
}

test_small_sql_not_flagged() {
  setup_fixture_dir
  create_file "schema.sql" "CREATE TABLE users (id INT);"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "data_dump" "small .sql not flagged"
  teardown_fixture_dir
}

# ============================================================
# Build artifact tests
# ============================================================

test_build_artifact_node_modules() {
  setup_fixture_dir
  mkdir -p "$FIXTURE_REPO/node_modules/some-pkg"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "MEDIUM|build_artifact" "detects node_modules/"
  teardown_fixture_dir
}

test_build_artifact_pycache() {
  setup_fixture_dir
  mkdir -p "$FIXTURE_REPO/__pycache__"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "MEDIUM|build_artifact" "detects __pycache__/"
  teardown_fixture_dir
}

# ============================================================
# OS artifact tests
# ============================================================

test_ds_store_detected() {
  setup_fixture_dir
  create_file ".DS_Store" ""
  run_check "$CHECK"
  assert_contains "$OUTPUT" "LOW|os_artifact" "detects .DS_Store"
  teardown_fixture_dir
}

# ============================================================
# Directory depth tests
# ============================================================

test_deep_directory_detected() {
  setup_fixture_dir
  create_deep_dirs 10
  run_check "$CHECK"
  assert_contains "$OUTPUT" "LOW|deep_directory" "detects nesting >8 levels"
  teardown_fixture_dir
}

test_shallow_directory_clean() {
  setup_fixture_dir
  create_deep_dirs 5
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "deep_directory" "5-level nesting is fine"
  teardown_fixture_dir
}

# ============================================================
# Run all tests
# ============================================================

echo ">> check_repo_hygiene.sh"
test_large_file_detected
test_small_file_not_flagged
test_log_file_detected
test_data_dump_detected
test_small_sql_not_flagged
test_build_artifact_node_modules
test_build_artifact_pycache
test_ds_store_detected
test_deep_directory_detected
test_shallow_directory_clean
print_summary
