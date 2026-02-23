#!/usr/bin/env bash
# test_framework.sh — Shared test utilities for scanner tests
# Source this file from each test_*.sh script.
# shellcheck disable=SC2034  # Variables used by sourcing scripts

set -euo pipefail

# --- Global counters ---
_PASS=0
_FAIL=0
_SKIP=0
_CURRENT_TEST=""
FIXTURE_REPO=""

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

# ============================================================
# Setup / Teardown
# ============================================================

setup_fixture_dir() {
  FIXTURE_REPO=$(mktemp -d)
  # Create a stub .git dir so scripts that exclude .git work properly
  mkdir -p "$FIXTURE_REPO/.git"
}

teardown_fixture_dir() {
  if [[ -n "$FIXTURE_REPO" && -d "$FIXTURE_REPO" ]]; then
    rm -rf "$FIXTURE_REPO"
  fi
  FIXTURE_REPO=""
}

# ============================================================
# Fixture Helpers
# ============================================================

# Create a file with content at a relative path inside FIXTURE_REPO
create_file() {
  local relpath="$1"
  local content="${2:-}"
  local fullpath="$FIXTURE_REPO/$relpath"
  mkdir -p "$(dirname "$fullpath")"
  printf '%s' "$content" > "$fullpath"
}

# Create a file with content ending in newline
create_file_ln() {
  local relpath="$1"
  local content="${2:-}"
  local fullpath="$FIXTURE_REPO/$relpath"
  mkdir -p "$(dirname "$fullpath")"
  printf '%s\n' "$content" > "$fullpath"
}

# Create an empty file
create_empty_file() {
  local relpath="$1"
  local fullpath="$FIXTURE_REPO/$relpath"
  mkdir -p "$(dirname "$fullpath")"
  : > "$fullpath"
}

# Create a file of approximately N megabytes (using /dev/zero)
create_file_of_size() {
  local relpath="$1"
  local size_mb="$2"
  local fullpath="$FIXTURE_REPO/$relpath"
  mkdir -p "$(dirname "$fullpath")"
  dd if=/dev/zero of="$fullpath" bs=1048576 count="$size_mb" 2>/dev/null
}

# Create nested directories to a given depth
create_deep_dirs() {
  local depth="$1"
  local path="$FIXTURE_REPO"
  for ((i = 1; i <= depth; i++)); do
    path="$path/level$i"
  done
  mkdir -p "$path"
}

# ============================================================
# Runner Helper
# ============================================================

# Run a check script against FIXTURE_REPO. Sets OUTPUT, STDERR, EXIT_CODE.
# Automatically asserts EXIT_CODE=0 (catches silent crashes).
# Usage: run_check "$SCANNER_DIR/check_something.sh"
run_check() {
  local script="$1"
  local repo="${2:-$FIXTURE_REPO}"
  local tmpout tmpeerr
  tmpout=$(mktemp)
  tmpeerr=$(mktemp)
  EXIT_CODE=0
  "$BASH" "$script" "$repo" > "$tmpout" 2> "$tmpeerr" || EXIT_CODE=$?
  OUTPUT=$(cat "$tmpout")
  STDERR=$(cat "$tmpeerr")
  rm -f "$tmpout" "$tmpeerr"
  if [[ "$EXIT_CODE" -ne 0 ]]; then
    _fail "run_check $(basename "$script")" "script exited with code $EXIT_CODE"
  fi
}

# ============================================================
# Assert Functions
# ============================================================

# Assert that output contains a fixed string (grep -qF)
assert_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    _pass "$description"
  else
    _fail "$description" "expected to find: $needle"
  fi
}

# Assert that output does NOT contain a fixed string
assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    _fail "$description" "expected NOT to find: $needle"
  else
    _pass "$description"
  fi
}

# Assert that output matches a regex pattern (grep -qE)
assert_matches() {
  local haystack="$1"
  local pattern="$2"
  local description="$3"
  if echo "$haystack" | grep -qE "$pattern"; then
    _pass "$description"
  else
    _fail "$description" "expected to match pattern: $pattern"
  fi
}

# Assert numeric equality
assert_equals() {
  local actual="$1"
  local expected="$2"
  local description="$3"
  if [[ "$actual" == "$expected" ]]; then
    _pass "$description"
  else
    _fail "$description" "expected '$expected', got '$actual'"
  fi
}

# Assert exit code
assert_exit_code() {
  local actual="$1"
  local expected="$2"
  local description="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    _pass "$description"
  else
    _fail "$description" "expected exit code $expected, got $actual"
  fi
}

# Skip a test
skip_test() {
  local description="$1"
  local reason="${2:-}"
  _SKIP=$((_SKIP + 1))
  printf "  ${_YELLOW}SKIP${_RESET}: %s" "$description"
  [[ -n "$reason" ]] && printf " (%s)" "$reason"
  printf "\n"
}

# ============================================================
# Internal Helpers
# ============================================================

_pass() {
  _PASS=$((_PASS + 1))
  printf "  ${_GREEN}PASS${_RESET}: %s\n" "$1"
}

_fail() {
  _FAIL=$((_FAIL + 1))
  printf "  ${_RED}FAIL${_RESET}: %s — %s\n" "$1" "$2"
}

# ============================================================
# Summary
# ============================================================

print_summary() {
  local total=$((_PASS + _FAIL + _SKIP))
  echo ""
  echo "--- Results: $total total | ${_PASS} passed | ${_FAIL} failed | ${_SKIP} skipped ---"
  if [[ "$_FAIL" -gt 0 ]]; then
    return 1
  fi
  return 0
}
