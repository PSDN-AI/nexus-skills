#!/usr/bin/env bash
# plan.sh — Main entry point for Spec Plan
# Usage: plan.sh <domain_dir> [options]
# Validates domain input and tasks.yaml output
set -euo pipefail

VERSION="0.1.0"

# Require bash 4+ (associative arrays)
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "Error: bash 4.0+ required (found ${BASH_VERSION})." >&2
  echo "  macOS: brew install bash" >&2
  echo "  Linux: sudo apt-get install bash" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Source library modules ---
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/validator.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/conflict-checker.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/coverage.sh"

# --- Defaults ---
DOMAIN_DIR=""
CONTRACTS_DIR=""
VALIDATE_ONLY=false
VERBOSE=false

# --- Parse arguments ---
show_usage() {
  cat <<EOF
Usage: plan.sh <domain_dir> [options]

Generate or validate tasks.yaml from a domain folder (prd-decompose output).

Arguments:
  domain_dir            Path to domain folder containing spec.md and boundary.yaml

Options:
  -c, --contracts DIR   Path to contracts directory for cross-domain context
  --validate-only       Validate existing tasks.yaml without re-planning
  -v, --verbose         Show detailed processing info
  --version             Print version and exit
  -h, --help            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      echo "spec-plan ${VERSION}"
      exit 0
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    -c|--contracts)
      CONTRACTS_DIR="${2:?--contracts requires a directory path}"
      shift 2
      ;;
    --validate-only)
      VALIDATE_ONLY=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      show_usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$DOMAIN_DIR" ]]; then
        DOMAIN_DIR="$1"
      else
        echo "Error: Unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

# --- Validate inputs ---
if [[ -z "$DOMAIN_DIR" ]]; then
  echo "Error: Domain directory path is required." >&2
  show_usage >&2
  exit 1
fi

if [[ ! -d "$DOMAIN_DIR" ]]; then
  echo "Error: Domain directory not found: ${DOMAIN_DIR}" >&2
  exit 1
fi

# Resolve to absolute path
DOMAIN_DIR=$(cd "$DOMAIN_DIR" && pwd)

log() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo "[spec-plan] $*" >&2
  fi
}

# Check required input files
SPEC_FILE="${DOMAIN_DIR}/spec.md"
BOUNDARY_FILE="${DOMAIN_DIR}/boundary.yaml"

if [[ ! -f "$SPEC_FILE" ]]; then
  echo "Error: spec.md not found in domain directory: ${DOMAIN_DIR}" >&2
  exit 1
fi

if [[ ! -f "$BOUNDARY_FILE" ]]; then
  echo "Error: boundary.yaml not found in domain directory: ${DOMAIN_DIR}" >&2
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "Error: yq v4+ is required." >&2
  echo "  macOS: brew install yq" >&2
  echo "  Linux: install mikefarah/yq v4+ from your package manager." >&2
  exit 1
fi

if ! yq --version 2>/dev/null | grep -qE 'version v([4-9]|[1-9][0-9])\.'; then
  echo "Error: yq v4+ (mikefarah/yq) is required." >&2
  exit 1
fi

log "Domain directory: ${DOMAIN_DIR}"
log "Spec file: ${SPEC_FILE}"
log "Boundary file: ${BOUNDARY_FILE}"

if [[ -n "$CONTRACTS_DIR" ]]; then
  if [[ ! -d "$CONTRACTS_DIR" ]]; then
    echo "Error: Contracts directory not found: ${CONTRACTS_DIR}" >&2
    exit 1
  fi
  CONTRACTS_DIR=$(cd "$CONTRACTS_DIR" && pwd)
  log "Contracts directory: ${CONTRACTS_DIR}"
fi

# --- Locate tasks.yaml ---
TASKS_FILE="${DOMAIN_DIR}/tasks.yaml"

# ============================================================
# Validate-only mode
# ============================================================
if [[ "$VALIDATE_ONLY" == "true" ]]; then
  if [[ ! -f "$TASKS_FILE" ]]; then
    echo "Error: tasks.yaml not found for validation: ${TASKS_FILE}" >&2
    exit 1
  fi

  echo "Validating tasks.yaml..."
  echo ""

  ERRORS=0

  # Step 1: Structure validation
  log "Running structure validation..."
  if validate_tasks_yaml "$TASKS_FILE"; then
    echo "  Structure:  PASS"
  else
    echo "  Structure:  FAIL"
    ERRORS=$((ERRORS + 1))
  fi

  # Step 2: File conflict check
  log "Running file conflict check..."
  if check_file_conflicts "$TASKS_FILE"; then
    echo "  Conflicts:  PASS"
  else
    echo "  Conflicts:  FAIL"
    ERRORS=$((ERRORS + 1))
  fi

  # Step 3: AC coverage check
  log "Running AC coverage check..."
  COVERAGE_OUTPUT=$(check_ac_coverage "$TASKS_FILE" "$BOUNDARY_FILE" 2>&1) && COV_EXIT=0 || COV_EXIT=$?
  if [[ "$COV_EXIT" -eq 0 ]]; then
    echo "  Coverage:   PASS"
  else
    echo "  Coverage:   FAIL"
    ERRORS=$((ERRORS + 1))
  fi
  echo ""
  echo "$COVERAGE_OUTPUT"

  if [[ "$ERRORS" -gt 0 ]]; then
    echo ""
    echo "Validation FAILED (${ERRORS} check(s) failed)"
    # Return the most specific exit code
    if ! validate_tasks_yaml "$TASKS_FILE" 2>/dev/null; then
      exit 2
    fi
    if ! check_file_conflicts "$TASKS_FILE" 2>/dev/null; then
      exit 3
    fi
    exit 4
  fi

  echo ""
  echo "Validation PASSED"

  # Print summary stats
  TOTAL_TASKS=$(yq -r '.tasks // [] | length' "$TASKS_FILE" 2>/dev/null || echo "0")
  TOTAL_PHASES=$(yq -r '.execution_plan // [] | length' "$TASKS_FILE" 2>/dev/null || echo "0")
  PARALLEL_TASKS=$(yq -r '.execution_plan // [] | map(select(.parallel == true)) | length' "$TASKS_FILE" 2>/dev/null || echo "0")

  echo ""
  echo "Summary:"
  echo "  Tasks:  ${TOTAL_TASKS}"
  echo "  Phases: ${TOTAL_PHASES}"
  echo "  Parallel phases: ${PARALLEL_TASKS}"

  exit 0
fi

# ============================================================
# Planning mode (AI-assisted)
# ============================================================
# spec-plan is Layer 1 primary — the AI reads SKILL.md and generates
# tasks.yaml. This script validates input and provides guidance.

echo "Spec Plan — Domain Task Graph Generator"
echo "========================================"
echo ""
echo "Domain:    $(basename "$DOMAIN_DIR")"
echo "Spec:      ${SPEC_FILE}"
echo "Boundary:  ${BOUNDARY_FILE}"

if [[ -n "$CONTRACTS_DIR" ]]; then
  echo "Contracts: ${CONTRACTS_DIR}"
  CONTRACTS_LIST=$(find "$CONTRACTS_DIR" -name '*.yaml' -o -name '*.yml' 2>/dev/null | sort)
  if [[ -n "$CONTRACTS_LIST" ]]; then
    echo ""
    echo "Available contracts:"
    echo "$CONTRACTS_LIST" | while IFS= read -r f; do
      echo "  - $(basename "$f")"
    done
  fi
fi

echo ""

# Count acceptance criteria
AC_COUNT=$(grep -c '  - id:' "$BOUNDARY_FILE" 2>/dev/null || echo "0")
P0_COUNT=$(grep -c 'priority: P0' "$BOUNDARY_FILE" 2>/dev/null || echo "0")
P1_COUNT=$(grep -c 'priority: P1' "$BOUNDARY_FILE" 2>/dev/null || echo "0")
P2_COUNT=$(grep -c 'priority: P2' "$BOUNDARY_FILE" 2>/dev/null || echo "0")

echo "Acceptance Criteria: ${AC_COUNT} total (P0:${P0_COUNT} P1:${P1_COUNT} P2:${P2_COUNT})"

# Check if tasks.yaml already exists
if [[ -f "$TASKS_FILE" ]]; then
  echo ""
  echo "Existing tasks.yaml found. Running validation..."
  echo ""

  ERRORS=0

  if validate_tasks_yaml "$TASKS_FILE"; then
    echo "  Structure:  PASS"
  else
    echo "  Structure:  FAIL"
    ERRORS=$((ERRORS + 1))
  fi

  if check_file_conflicts "$TASKS_FILE"; then
    echo "  Conflicts:  PASS"
  else
    echo "  Conflicts:  FAIL"
    ERRORS=$((ERRORS + 1))
  fi

  COVERAGE_OUTPUT=$(check_ac_coverage "$TASKS_FILE" "$BOUNDARY_FILE" 2>&1) && COV_EXIT=0 || COV_EXIT=$?
  if [[ "$COV_EXIT" -eq 0 ]]; then
    echo "  Coverage:   PASS"
  else
    echo "  Coverage:   FAIL"
    ERRORS=$((ERRORS + 1))
  fi
  echo ""
  echo "$COVERAGE_OUTPUT"

  if [[ "$ERRORS" -eq 0 ]]; then
    echo ""
    echo "All validations passed."
  else
    echo ""
    echo "${ERRORS} validation(s) failed. Review and fix tasks.yaml."
  fi
else
  echo ""
  echo "No tasks.yaml found. Use SKILL.md to guide AI through task planning."
  echo ""
  echo "Next steps:"
  echo "  1. Read SKILL.md for the 7-phase planning workflow"
  echo "  2. Generate tasks.yaml following the output schema"
  echo "  3. Run: plan.sh ${DOMAIN_DIR} --validate-only"
fi
