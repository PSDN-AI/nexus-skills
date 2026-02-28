#!/usr/bin/env bash
# run_tests.sh — Entry point for all scanner tests
# Usage: run_tests.sh
set -euo pipefail

# Require bash 4+
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "Error: bash 4.0+ required (found ${BASH_VERSION})." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANNER_DIR="$(cd "$SCRIPT_DIR/../scripts" && pwd)"

SUITE_FAILURES=0

echo "============================================"
echo "  Repo Audit Scanner — Test Suite"
echo "============================================"
echo ""

for test_file in "$SCRIPT_DIR"/test_check_*.sh "$SCRIPT_DIR"/test_run_scan.sh; do
  [[ -f "$test_file" ]] || continue
  basename_f=$(basename "$test_file")

  if "$BASH" "$test_file" "$SCANNER_DIR"; then
    echo "  ✅ $basename_f"
  else
    echo "  ❌ $basename_f"
    SUITE_FAILURES=$((SUITE_FAILURES + 1))
  fi
  echo ""
done

echo "============================================"
if [[ "$SUITE_FAILURES" -gt 0 ]]; then
  echo "  ❌ $SUITE_FAILURES test file(s) had failures"
  echo "============================================"
  exit 1
else
  echo "  ✅ All test files passed"
  echo "============================================"
  exit 0
fi
