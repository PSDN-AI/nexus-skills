#!/usr/bin/env bash
# test_check_documentation.sh — Tests for check_documentation.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANNER_DIR="${1:?Usage: test_check_documentation.sh <scanner_dir>}"

# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

CHECK="$SCANNER_DIR/check_documentation.sh"

# ============================================================
# README tests
# ============================================================

test_readme_missing() {
  setup_fixture_dir
  run_check "$CHECK"
  assert_contains "$OUTPUT" "HIGH|readme_missing" "detects missing README"
  teardown_fixture_dir
}

test_readme_thin() {
  setup_fixture_dir
  create_file "README.md" "# Hi"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "HIGH|readme_thin" "detects thin README (<500 chars, <50 lines)"
  teardown_fixture_dir
}

test_readme_adequate_by_chars() {
  setup_fixture_dir
  # 600+ chars, only 20 lines
  local content
  content=$(printf 'This is a project readme with enough content.\n%.0s' {1..20})
  create_file "README.md" "$content"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "readme_thin" "README with 600+ chars is adequate"
  assert_not_contains "$OUTPUT" "readme_missing" "README exists"
  teardown_fixture_dir
}

test_readme_adequate_by_lines() {
  setup_fixture_dir
  # 55 lines, short content per line
  local content=""
  for i in $(seq 1 55); do
    content+="line $i"$'\n'
  done
  create_file "README.md" "$content"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "readme_thin" "README with 55 lines is adequate"
  teardown_fixture_dir
}

test_readme_rst_variant() {
  setup_fixture_dir
  local content
  content=$(printf 'This is a project readme with enough content.\n%.0s' {1..20})
  create_file "README.rst" "$content"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "readme_missing" "README.rst is recognized"
  teardown_fixture_dir
}

# ============================================================
# LICENSE tests
# ============================================================

test_license_missing() {
  setup_fixture_dir
  run_check "$CHECK"
  assert_contains "$OUTPUT" "HIGH|license_missing" "detects missing LICENSE"
  teardown_fixture_dir
}

test_license_present() {
  setup_fixture_dir
  create_file "LICENSE" "MIT License"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "license_missing" "LICENSE present"
  teardown_fixture_dir
}

test_licence_uk_spelling() {
  setup_fixture_dir
  create_file "LICENCE" "MIT License"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "license_missing" "LICENCE (UK spelling) recognized"
  teardown_fixture_dir
}

# ============================================================
# CONTRIBUTING tests
# ============================================================

test_contributing_missing() {
  setup_fixture_dir
  run_check "$CHECK"
  assert_contains "$OUTPUT" "MEDIUM|contributing_missing" "detects missing CONTRIBUTING.md"
  teardown_fixture_dir
}

test_contributing_present() {
  setup_fixture_dir
  create_file "CONTRIBUTING.md" "# How to contribute"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "contributing_missing" "CONTRIBUTING.md present"
  teardown_fixture_dir
}

# ============================================================
# .gitignore tests
# ============================================================

test_gitignore_missing() {
  setup_fixture_dir
  run_check "$CHECK"
  assert_contains "$OUTPUT" "MEDIUM|gitignore_missing" "detects missing .gitignore"
  teardown_fixture_dir
}

test_gitignore_present() {
  setup_fixture_dir
  create_file ".gitignore" "node_modules/"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "gitignore_missing" ".gitignore present"
  teardown_fixture_dir
}

# ============================================================
# Code of Conduct tests
# ============================================================

test_coc_missing() {
  setup_fixture_dir
  run_check "$CHECK"
  assert_contains "$OUTPUT" "LOW|coc_missing" "detects missing Code of Conduct"
  teardown_fixture_dir
}

test_coc_in_github_dir() {
  setup_fixture_dir
  create_file ".github/CODE_OF_CONDUCT.md" "# Code of Conduct"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "coc_missing" "CoC in .github/ recognized"
  teardown_fixture_dir
}

# ============================================================
# SECURITY.md and CHANGELOG tests
# ============================================================

test_security_md_missing() {
  setup_fixture_dir
  run_check "$CHECK"
  assert_contains "$OUTPUT" "MEDIUM|security_md_missing" "detects missing SECURITY.md"
  teardown_fixture_dir
}

test_changelog_missing() {
  setup_fixture_dir
  run_check "$CHECK"
  assert_contains "$OUTPUT" "LOW|changelog_missing" "detects missing CHANGELOG"
  teardown_fixture_dir
}

# ============================================================
# Run all tests
# ============================================================

echo ">> check_documentation.sh"
test_readme_missing
test_readme_thin
test_readme_adequate_by_chars
test_readme_adequate_by_lines
test_readme_rst_variant
test_license_missing
test_license_present
test_licence_uk_spelling
test_contributing_missing
test_contributing_present
test_gitignore_missing
test_gitignore_present
test_coc_missing
test_coc_in_github_dir
test_security_md_missing
test_changelog_missing
print_summary
