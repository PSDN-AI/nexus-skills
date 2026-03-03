#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../pre-commit"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TEST_REPO=""
HOOK_OUTPUT=""
HOOK_EXIT_CODE=0

cleanup() {
  if [[ -n "$TEST_REPO" && -d "$TEST_REPO" ]]; then
    rm -rf "$TEST_REPO"
  fi
  TEST_REPO=""
}

trap cleanup EXIT

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf "  PASS: %s\n" "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "  FAIL: %s -- %s\n" "$1" "$2"
}

skip() {
  SKIP_COUNT=$((SKIP_COUNT + 1))
  printf "  SKIP: %s" "$1"
  if [[ -n "${2:-}" ]]; then
    printf " (%s)" "$2"
  fi
  printf "\n"
}

assert_exit_code() {
  local actual="$1"
  local expected="$2"
  local description="$3"

  if [[ "$actual" -eq "$expected" ]]; then
    pass "$description"
  else
    fail "$description" "expected exit $expected, got $actual; output: $HOOK_OUTPUT"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"

  if printf '%s' "$haystack" | grep -qF "$needle"; then
    pass "$description"
  else
    fail "$description" "expected output to contain '$needle'; output: $haystack"
  fi
}

setup_repo() {
  cleanup
  TEST_REPO=$(mktemp -d)
  git -C "$TEST_REPO" init -q
  git -C "$TEST_REPO" config user.name "Hook Test"
  git -C "$TEST_REPO" config user.email "hook-test@example.com"
}

write_file() {
  local relpath="$1"
  local content="$2"
  local fullpath="$TEST_REPO/$relpath"

  mkdir -p "$(dirname "$fullpath")"
  printf '%s' "$content" > "$fullpath"
}

stage_file() {
  local relpath="$1"
  git -C "$TEST_REPO" add -- "$relpath"
}

run_hook() {
  local tmpout
  tmpout=$(mktemp)
  HOOK_EXIT_CODE=0

  (
    cd "$TEST_REPO"
    "$BASH" "$HOOK_SCRIPT"
  ) >"$tmpout" 2>&1 || HOOK_EXIT_CODE=$?

  HOOK_OUTPUT=$(cat "$tmpout")
  rm -f "$tmpout"
}

test_uses_staged_snapshot() {
  setup_repo
  write_file "script.sh" $'#!/usr/bin/env bash\necho "staged"\n'
  stage_file "script.sh"
  write_file "script.sh" $'#!/usr/bin/env bash\nfoo=bar\n'

  run_hook

  assert_exit_code "$HOOK_EXIT_CODE" 0 "uses staged content instead of unstaged edits"
}

test_handles_spaces_in_paths() {
  setup_repo
  write_file "scripts/script with space.sh" $'#!/usr/bin/env bash\necho "ok"\n'
  stage_file "scripts/script with space.sh"

  run_hook

  assert_exit_code "$HOOK_EXIT_CODE" 0 "handles staged paths with spaces"
}

test_checks_extensionless_sh_shebang() {
  setup_repo
  write_file "tool" $'#!/usr/bin/env sh\nfoo=bar\n'
  stage_file "tool"

  run_hook

  assert_exit_code "$HOOK_EXIT_CODE" 1 "checks extensionless sh shebang scripts"
  assert_contains "$HOOK_OUTPUT" "tool" "reports the failing extensionless script path"
}

main() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    skip "pre-commit hook tests" "shellcheck is not installed"
    return 0
  fi

  test_uses_staged_snapshot
  test_handles_spaces_in_paths
  test_checks_extensionless_sh_shebang

  echo ""
  echo "--- Results: $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT)) total | ${PASS_COUNT} passed | ${FAIL_COUNT} failed | ${SKIP_COUNT} skipped ---"

  if [[ "$FAIL_COUNT" -gt 0 ]]; then
    return 1
  fi
}

main "$@"
