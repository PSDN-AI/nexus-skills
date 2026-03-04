#!/usr/bin/env bash
# run_tests.sh — Entry point for Agent Launcher tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "======================================="
echo " Agent Launcher Test Suite"
echo "======================================="
echo ""

OVERALL_EXIT=0

"$BASH" "$SCRIPT_DIR/test_launcher.sh" || OVERALL_EXIT=1

echo ""
if [[ "$OVERALL_EXIT" -eq 0 ]]; then
  echo "All test suites passed."
else
  echo "Some test suites failed."
fi

exit "$OVERALL_EXIT"
