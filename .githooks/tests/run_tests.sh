#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "======================================="
echo " Git Hook Test Suite"
echo "======================================="
echo ""

OVERALL_EXIT=0

"$BASH" "$SCRIPT_DIR/test_pre_commit.sh" || OVERALL_EXIT=1

echo ""
if [[ "$OVERALL_EXIT" -eq 0 ]]; then
  echo "All test suites passed."
else
  echo "Some test suites failed."
fi

exit "$OVERALL_EXIT"
