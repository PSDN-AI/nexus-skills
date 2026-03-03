#!/usr/bin/env bash
# run_tests.sh — Entry point for gha-create test suite.
#
# Usage: bash tests/run_tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "======================================="
echo " GHA Create — Test Suite"
echo "======================================="
echo ""

OVERALL_EXIT=0

echo "--- test_validate.sh ---"
if bash "$SCRIPT_DIR/test_validate.sh" "$SCRIPT_DIR/.."; then
  echo "  ✅ test_validate.sh passed"
else
  echo "  ❌ test_validate.sh failed"
  OVERALL_EXIT=1
fi

echo ""
if [[ "$OVERALL_EXIT" -eq 0 ]]; then
  echo "All test suites passed."
else
  echo "Some test suites failed."
fi
exit "$OVERALL_EXIT"
