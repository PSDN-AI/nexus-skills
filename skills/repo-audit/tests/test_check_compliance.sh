#!/usr/bin/env bash
# test_check_compliance.sh — Tests for check_compliance.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANNER_DIR="${1:?Usage: test_check_compliance.sh <scanner_dir>}"

# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

CHECK="$SCANNER_DIR/check_compliance.sh"

# ============================================================
# License recognition tests
# ============================================================

test_mit_license_recognized() {
  setup_fixture_dir
  create_file_ln "LICENSE" "MIT License

Copyright (c) 2024 Test

Permission is hereby granted, free of charge, to any person..."
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "license_unrecognized" "MIT license recognized"
  teardown_fixture_dir
}

test_apache_license_recognized() {
  setup_fixture_dir
  create_file_ln "LICENSE" "Apache License
Version 2.0, January 2004"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "license_unrecognized" "Apache license recognized"
  teardown_fixture_dir
}

test_unrecognized_license() {
  setup_fixture_dir
  create_file_ln "LICENSE" "This is my own custom license.
You may not do anything with this code."
  run_check "$CHECK"
  assert_contains "$OUTPUT" "HIGH|license_unrecognized" "custom license flagged"
  teardown_fixture_dir
}

test_missing_license_compliance() {
  setup_fixture_dir
  run_check "$CHECK"
  assert_contains "$OUTPUT" "HIGH|license_missing" "missing LICENSE detected"
  teardown_fixture_dir
}

# ============================================================
# Internal reference tests
# ============================================================

test_internal_only_detected() {
  setup_fixture_dir
  create_file_ln "README.md" "This document is internal-only and should not be shared."
  run_check "$CHECK"
  assert_contains "$OUTPUT" "HIGH|internal_reference" "detects 'internal-only'"
  teardown_fixture_dir
}

test_company_confidential_detected() {
  setup_fixture_dir
  create_file_ln "doc.md" "This is company-confidential material."
  run_check "$CHECK"
  assert_contains "$OUTPUT" "HIGH|internal_reference" "detects 'company-confidential'"
  teardown_fixture_dir
}

test_custom_keyword_via_env() {
  setup_fixture_dir
  create_file_ln "notes.md" "Contact acme-corp for details."
  SCAN_INTERNAL_KEYWORDS="acme-corp" run_check "$CHECK"
  assert_contains "$OUTPUT" "HIGH|internal_reference" "custom keyword via SCAN_INTERNAL_KEYWORDS"
  teardown_fixture_dir
}

test_no_internal_refs_clean() {
  setup_fixture_dir
  create_file_ln "README.md" "# My Project

This is a great open-source project for everyone."
  create_file_ln "LICENSE" "MIT License"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "internal_reference" "clean repo has no internal refs"
  teardown_fixture_dir
}

# ============================================================
# Scanner dir self-exclusion test
# ============================================================

test_scanner_dir_self_excluded() {
  setup_fixture_dir
  # The compliance script excludes paths matching /repo-audit/scripts/
  mkdir -p "$FIXTURE_REPO/repo-audit/scripts"
  create_file_ln "repo-audit/scripts/check.sh" "# internal-only comment"
  create_file_ln "LICENSE" "MIT License"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "internal_reference" "scanner dir self-excluded from internal ref scan"
  teardown_fixture_dir
}

# ============================================================
# Copyright headers test
# ============================================================

test_missing_copyright_headers_reported() {
  setup_fixture_dir
  create_file_ln "LICENSE" "MIT License"
  # Create 20 .py files without copyright headers
  for i in $(seq 1 20); do
    create_file_ln "module_${i}.py" "def func_${i}():
    pass"
  done
  run_check "$CHECK"
  assert_contains "$OUTPUT" "LOW|copyright_headers" "missing copyright headers reported"
  teardown_fixture_dir
}

# ============================================================
# Run all tests
# ============================================================

echo ">> check_compliance.sh"
test_mit_license_recognized
test_apache_license_recognized
test_unrecognized_license
test_missing_license_compliance
test_internal_only_detected
test_company_confidential_detected
test_custom_keyword_via_env
test_no_internal_refs_clean
test_scanner_dir_self_excluded
test_missing_copyright_headers_reported
print_summary
