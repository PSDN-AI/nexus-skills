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
  # check_code_quality.sh excludes paths matching /repo-audit/scripts/
  mkdir -p "$FIXTURE_REPO/repo-audit/scripts"
  create_file_ln "repo-audit/scripts/check.sh" "# TODO: this should be excluded"
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
# Python linter configuration detection
# ============================================================

test_python_no_linter_detected() {
  setup_fixture_dir
  create_file_ln "app.py" "print('hello')"
  echo "requests" > "$FIXTURE_REPO/requirements.txt"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "LOW|python_no_linter" "detects missing Python linter"
  teardown_fixture_dir
}

test_python_ruff_toml_suppresses_linter() {
  setup_fixture_dir
  create_file_ln "app.py" "print('hello')"
  echo "requests" > "$FIXTURE_REPO/requirements.txt"
  printf '[lint]\nselect = ["E", "F"]\n' > "$FIXTURE_REPO/ruff.toml"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "python_no_linter" "ruff.toml suppresses linter warning"
  teardown_fixture_dir
}

test_python_pyproject_ruff_suppresses_linter() {
  setup_fixture_dir
  create_file_ln "app.py" "print('hello')"
  printf '[tool.ruff]\nline-length = 88\n' > "$FIXTURE_REPO/pyproject.toml"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "python_no_linter" "pyproject.toml [tool.ruff] suppresses linter warning"
  teardown_fixture_dir
}

test_python_flake8_suppresses_linter() {
  setup_fixture_dir
  create_file_ln "app.py" "print('hello')"
  echo "requests" > "$FIXTURE_REPO/requirements.txt"
  touch "$FIXTURE_REPO/.flake8"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "python_no_linter" ".flake8 suppresses linter warning"
  teardown_fixture_dir
}

test_python_precommit_ruff_suppresses_linter() {
  setup_fixture_dir
  create_file_ln "app.py" "print('hello')"
  echo "requests" > "$FIXTURE_REPO/requirements.txt"
  printf 'repos:\n  - repo: https://github.com/astral-sh/ruff-pre-commit\n    hooks:\n      - id: ruff\n' > "$FIXTURE_REPO/.pre-commit-config.yaml"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "python_no_linter" "pre-commit ruff suppresses linter warning"
  teardown_fixture_dir
}

# ============================================================
# Python type checker configuration detection
# ============================================================

test_python_no_typechecker_detected() {
  setup_fixture_dir
  create_file_ln "app.py" "print('hello')"
  echo "requests" > "$FIXTURE_REPO/requirements.txt"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "LOW|python_no_typechecker" "detects missing Python type checker"
  teardown_fixture_dir
}

test_python_mypy_ini_suppresses_typechecker() {
  setup_fixture_dir
  create_file_ln "app.py" "print('hello')"
  echo "requests" > "$FIXTURE_REPO/requirements.txt"
  printf '[mypy]\nstrict = True\n' > "$FIXTURE_REPO/mypy.ini"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "python_no_typechecker" "mypy.ini suppresses type checker warning"
  teardown_fixture_dir
}

test_python_pyproject_mypy_suppresses_typechecker() {
  setup_fixture_dir
  create_file_ln "app.py" "print('hello')"
  printf '[tool.mypy]\nstrict = true\n' > "$FIXTURE_REPO/pyproject.toml"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "python_no_typechecker" "pyproject.toml [tool.mypy] suppresses type checker warning"
  teardown_fixture_dir
}

test_python_pyrightconfig_suppresses_typechecker() {
  setup_fixture_dir
  create_file_ln "app.py" "print('hello')"
  echo "requests" > "$FIXTURE_REPO/requirements.txt"
  echo '{}' > "$FIXTURE_REPO/pyrightconfig.json"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "python_no_typechecker" "pyrightconfig.json suppresses type checker warning"
  teardown_fixture_dir
}

test_python_poetry_ruff_dep_suppresses_linter() {
  setup_fixture_dir
  create_file_ln "app.py" "print('hello')"
  printf '[tool.poetry.group.dev.dependencies]\nruff = "^0.5.0"\n' > "$FIXTURE_REPO/pyproject.toml"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "python_no_linter" "Poetry ruff dependency suppresses linter warning"
  teardown_fixture_dir
}

test_python_poetry_mypy_dep_suppresses_typechecker() {
  setup_fixture_dir
  create_file_ln "app.py" "print('hello')"
  printf '[tool.poetry.group.dev.dependencies]\nmypy = "^1.0"\n' > "$FIXTURE_REPO/pyproject.toml"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "python_no_typechecker" "Poetry mypy dependency suppresses type checker warning"
  teardown_fixture_dir
}

test_python_poetry_no_linter_still_flags() {
  setup_fixture_dir
  create_file_ln "app.py" "print('hello')"
  printf '[tool.poetry.group.dev.dependencies]\nrequests = "^2.31"\npytest = "^7.0"\n' > "$FIXTURE_REPO/pyproject.toml"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "LOW|python_no_linter" "Poetry deps without linter still flags"
  teardown_fixture_dir
}

test_python_poetry_no_typechecker_still_flags() {
  setup_fixture_dir
  create_file_ln "app.py" "print('hello')"
  printf '[tool.poetry.group.dev.dependencies]\nrequests = "^2.31"\nruff = "^0.5.0"\n' > "$FIXTURE_REPO/pyproject.toml"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "LOW|python_no_typechecker" "Poetry deps without typechecker still flags"
  teardown_fixture_dir
}

test_non_python_skips_checks() {
  setup_fixture_dir
  echo '{}' > "$FIXTURE_REPO/package.json"
  create_file_ln "index.js" "console.log('hello')"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "python_no_linter" "non-Python project skips linter check"
  assert_not_contains "$OUTPUT" "python_no_typechecker" "non-Python project skips type checker check"
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
test_python_no_linter_detected
test_python_ruff_toml_suppresses_linter
test_python_pyproject_ruff_suppresses_linter
test_python_flake8_suppresses_linter
test_python_precommit_ruff_suppresses_linter
test_python_no_typechecker_detected
test_python_mypy_ini_suppresses_typechecker
test_python_pyproject_mypy_suppresses_typechecker
test_python_pyrightconfig_suppresses_typechecker
test_python_poetry_ruff_dep_suppresses_linter
test_python_poetry_mypy_dep_suppresses_typechecker
test_python_poetry_no_linter_still_flags
test_python_poetry_no_typechecker_still_flags
test_non_python_skips_checks
print_summary
