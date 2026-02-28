#!/usr/bin/env bash
# test_validate.sh — Tests for validate_workflow.sh
#
# Usage: bash test_validate.sh <skill-dir>
# Example: bash test_validate.sh ../

set -euo pipefail

SKILL_DIR="${1:?Usage: $0 <skill-dir>}"
VALIDATOR="$SKILL_DIR/scripts/validate_workflow.sh"

# ---- Test framework ----
_PASS=0
_FAIL=0

assert_exit_code() {
  local actual="$1" expected="$2" desc="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    _PASS=$((_PASS + 1))
    echo "  ✅ $desc"
  else
    _FAIL=$((_FAIL + 1))
    echo "  ❌ $desc (expected exit $expected, got $actual)"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" desc="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    _PASS=$((_PASS + 1))
    echo "  ✅ $desc"
  else
    _FAIL=$((_FAIL + 1))
    echo "  ❌ $desc (expected to find: $needle)"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" desc="$3"
  if ! echo "$haystack" | grep -qF "$needle"; then
    _PASS=$((_PASS + 1))
    echo "  ✅ $desc"
  else
    _FAIL=$((_FAIL + 1))
    echo "  ❌ $desc (expected NOT to find: $needle)"
  fi
}

print_summary() {
  echo ""
  echo "Results: $_PASS passed, $_FAIL failed"
  if [[ $_FAIL -gt 0 ]]; then
    return 1
  fi
  return 0
}

# Helper: create a temp workflow file with given content
make_workflow() {
  local tmpfile
  tmpfile=$(mktemp /tmp/gha-test-XXXXXX.yml)
  cat > "$tmpfile"
  echo "$tmpfile"
}

# Helper: run validator, capture output and exit code
run_validator() {
  local file="$1"
  local output exit_code
  output=$(bash "$VALIDATOR" "$file" 2>&1) || true
  # Re-run to get actual exit code
  bash "$VALIDATOR" "$file" > /dev/null 2>&1 && exit_code=0 || exit_code=$?
  echo "$exit_code|$output"
}

# ---- Positive tests: Asset templates pass ----
echo ""
echo "=== Positive tests: Asset templates ==="

for template in "$SKILL_DIR"/assets/*.yml; do
  name=$(basename "$template")
  result=$(run_validator "$template")
  code="${result%%|*}"
  output="${result#*|}"
  assert_exit_code "$code" 0 "$name passes validation"
  assert_not_contains "$output" "FAIL" "$name has no FAIL results"
done

# ---- Positive test: after.yml passes ----
echo ""
echo "=== Positive test: after.yml ==="
result=$(run_validator "$SKILL_DIR/examples/after.yml")
code="${result%%|*}"
output="${result#*|}"
assert_exit_code "$code" 0 "after.yml passes validation"
assert_not_contains "$output" "FAIL" "after.yml has no FAIL results"

# ---- Negative test: before.yml fails ----
echo ""
echo "=== Negative test: before.yml ==="
result=$(run_validator "$SKILL_DIR/examples/before.yml")
code="${result%%|*}"
output="${result#*|}"
assert_exit_code "$code" 1 "before.yml fails validation"
assert_contains "$output" "FAIL: S1" "before.yml fails S1 (SHA pinning)"
assert_contains "$output" "FAIL: S2" "before.yml fails S2 (permissions)"
assert_contains "$output" "FAIL: S4" "before.yml fails S4 (injection)"
assert_contains "$output" "FAIL: E2" "before.yml fails E2 (caching)"
assert_contains "$output" "FAIL: E3" "before.yml fails E3 (concurrency)"

# ---- Targeted tests: S1 SHA pinning ----
echo ""
echo "=== Targeted tests: S1 SHA Pinning ==="

# Mutable tag
tmpfile=$(make_workflow <<'YAML'
name: test
on: push
permissions:
  contents: read
concurrency:
  group: test
  cancel-in-progress: true
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
YAML
)
result=$(run_validator "$tmpfile")
code="${result%%|*}"
output="${result#*|}"
assert_exit_code "$code" 1 "mutable tag fails S1"
assert_contains "$output" "FAIL: S1" "reports S1 failure for mutable tag"
rm -f "$tmpfile"

# Local action should not trigger S1
tmpfile=$(make_workflow <<'YAML'
name: test
on: push
permissions:
  contents: read
concurrency:
  group: test
  cancel-in-progress: true
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: ./my-local-action
YAML
)
result=$(run_validator "$tmpfile")
code="${result%%|*}"
output="${result#*|}"
assert_exit_code "$code" 0 "local action does not trigger S1"
assert_not_contains "$output" "FAIL: S1" "no S1 failure for local action"
rm -f "$tmpfile"

# SHA without version comment
tmpfile=$(make_workflow <<'YAML'
name: test
on: push
permissions:
  contents: read
concurrency:
  group: test
  cancel-in-progress: true
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
YAML
)
result=$(run_validator "$tmpfile")
code="${result%%|*}"
output="${result#*|}"
assert_exit_code "$code" 1 "SHA without version comment fails"
assert_contains "$output" "FAIL: S1" "reports S1 failure for missing comment"
rm -f "$tmpfile"

# ---- Targeted tests: S2 Permissions ----
echo ""
echo "=== Targeted tests: S2 Permissions ==="

# No permissions block
tmpfile=$(make_workflow <<'YAML'
name: test
on: push
concurrency:
  group: test
  cancel-in-progress: true
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: ./my-action
YAML
)
result=$(run_validator "$tmpfile")
code="${result%%|*}"
output="${result#*|}"
assert_contains "$output" "FAIL: S2" "no permissions block fails S2"
rm -f "$tmpfile"

# Empty permissions object is valid
tmpfile=$(make_workflow <<'YAML'
name: test
on: push
permissions: {}
concurrency:
  group: test
  cancel-in-progress: true
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: ./my-action
YAML
)
result=$(run_validator "$tmpfile")
code="${result%%|*}"
output="${result#*|}"
assert_not_contains "$output" "FAIL: S2" "empty permissions object passes S2"
rm -f "$tmpfile"

# ---- Targeted tests: S4 Injection ----
echo ""
echo "=== Targeted tests: S4 Injection ==="

# Direct interpolation in run block
tmpfile=$(make_workflow <<'YAML'
name: test
on: push
permissions:
  contents: read
concurrency:
  group: test
  cancel-in-progress: true
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo "${{ github.event.issue.title }}"
YAML
)
result=$(run_validator "$tmpfile")
code="${result%%|*}"
output="${result#*|}"
assert_contains "$output" "FAIL: S4" "direct interpolation in run: fails S4"
rm -f "$tmpfile"

# Multi-line run block with injection
tmpfile=$(make_workflow <<'YAML'
name: test
on: push
permissions:
  contents: read
concurrency:
  group: test
  cancel-in-progress: true
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: |
          echo "hello"
          echo "${{ github.event.pull_request.body }}"
YAML
)
result=$(run_validator "$tmpfile")
code="${result%%|*}"
output="${result#*|}"
assert_contains "$output" "FAIL: S4" "injection in multi-line run: fails S4"
rm -f "$tmpfile"

# Safe context in run block should pass
tmpfile=$(make_workflow <<'YAML'
name: test
on: push
permissions:
  contents: read
concurrency:
  group: test
  cancel-in-progress: true
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo "${{ github.repository }}"
YAML
)
result=$(run_validator "$tmpfile")
code="${result%%|*}"
output="${result#*|}"
assert_not_contains "$output" "FAIL: S4" "safe context passes S4"
rm -f "$tmpfile"

# ---- Targeted tests: E2 Caching ----
echo ""
echo "=== Targeted tests: E2 Caching ==="

# setup-node without cache
tmpfile=$(make_workflow <<'YAML'
name: test
on: push
permissions:
  contents: read
concurrency:
  group: test
  cancel-in-progress: true
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@6044e13b5dc448c55e2357c09f80417699197238 # v6.2.0
        with:
          node-version: 20
      - run: npm test
YAML
)
result=$(run_validator "$tmpfile")
code="${result%%|*}"
output="${result#*|}"
assert_contains "$output" "FAIL: E2" "setup-node without cache fails E2"
rm -f "$tmpfile"

# setup-node with cache
tmpfile=$(make_workflow <<'YAML'
name: test
on: push
permissions:
  contents: read
concurrency:
  group: test
  cancel-in-progress: true
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@6044e13b5dc448c55e2357c09f80417699197238 # v6.2.0
        with:
          node-version: 20
          cache: 'npm'
      - run: npm test
YAML
)
result=$(run_validator "$tmpfile")
code="${result%%|*}"
output="${result#*|}"
assert_not_contains "$output" "FAIL: E2" "setup-node with cache passes E2"
rm -f "$tmpfile"

# ---- Targeted tests: E3 Concurrency ----
echo ""
echo "=== Targeted tests: E3 Concurrency ==="

# No concurrency block
tmpfile=$(make_workflow <<'YAML'
name: test
on: push
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: ./my-action
YAML
)
result=$(run_validator "$tmpfile")
code="${result%%|*}"
output="${result#*|}"
assert_contains "$output" "FAIL: E3" "no concurrency block fails E3"
rm -f "$tmpfile"

# ---- Targeted tests: E4 Matrix ----
echo ""
echo "=== Targeted tests: E4 Matrix ==="

# Matrix with fail-fast: false
tmpfile=$(make_workflow <<'YAML'
name: test
on: push
permissions:
  contents: read
concurrency:
  group: test
  cancel-in-progress: true
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        node: [18, 20]
    steps:
      - uses: ./my-action
YAML
)
result=$(run_validator "$tmpfile")
code="${result%%|*}"
output="${result#*|}"
assert_contains "$output" "ADVISORY: E4" "fail-fast: false triggers E4 advisory"
rm -f "$tmpfile"

# ---- Edge case: File with no uses: lines ----
echo ""
echo "=== Edge case tests ==="

tmpfile=$(make_workflow <<'YAML'
name: test
on: push
permissions:
  contents: read
concurrency:
  group: test
  cancel-in-progress: true
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo "hello"
YAML
)
result=$(run_validator "$tmpfile")
code="${result%%|*}"
output="${result#*|}"
assert_exit_code "$code" 0 "file with no uses: lines passes"
rm -f "$tmpfile"

# ---- Print summary ----
print_summary
