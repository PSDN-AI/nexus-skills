#!/usr/bin/env bash
# validate_workflow.sh — Validate a GitHub Actions workflow against
# gha-create security and efficiency best practices.
#
# Usage: ./validate_workflow.sh <workflow-file>
# Exit 0 = all required checks pass
# Exit 1 = one or more required checks failed
#
# Checks: S1 (SHA pinning), S2 (permissions), S3 (OIDC, advisory),
#          S4 (injection), E1 (path filtering, advisory), E2 (caching),
#          E3 (concurrency), E4 (matrix fail-fast, advisory)

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <workflow-file>" >&2
  exit 2
fi

FILE="$1"

if [[ ! -f "$FILE" ]]; then
  echo "Error: file not found: $FILE" >&2
  exit 2
fi

BASENAME=$(basename "$FILE")
PASS=0
FAIL=0
ADVISORY=0
RESULTS=""

pass() {
  RESULTS+="- PASS: $1"$'\n'
  PASS=$((PASS + 1))
}

fail() {
  RESULTS+="- FAIL: $1"$'\n'
  FAIL=$((FAIL + 1))
}

advisory() {
  RESULTS+="- ADVISORY: $1"$'\n'
  ADVISORY=$((ADVISORY + 1))
}

# Portable grep -c that returns 0 instead of failing on no match
count_matches() {
  grep -cE "$1" "$2" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# S1: SHA Pinning
# Every uses: (except local ./ actions) must reference a 40-char hex SHA
# and include a version comment (# vX.Y.Z)
# ---------------------------------------------------------------------------
check_s1() {
  local violations=0
  local comment_violations=0

  while IFS= read -r line; do
    # Skip local actions
    if [[ "$line" =~ uses:[[:space:]]*\./ ]]; then
      continue
    fi
    # Skip Docker images, which use container tags instead of Git refs
    if [[ "$line" =~ uses:[[:space:]]*docker:// ]]; then
      continue
    fi
    # Check for 40-char SHA
    if [[ ! "$line" =~ @[0-9a-f]{40} ]]; then
      violations=$((violations + 1))
    else
      # SHA is present, check for version comment
      if [[ ! "$line" =~ \#[[:space:]]*v[0-9] ]]; then
        comment_violations=$((comment_violations + 1))
      fi
    fi
  done < <(grep -E '^[[:space:]]*-?[[:space:]]*uses:' "$FILE" 2>/dev/null || true)

  if [[ $violations -eq 0 && $comment_violations -eq 0 ]]; then
    pass "S1 -- SHA Pinning"
  else
    local msg="S1 -- SHA Pinning"
    if [[ $violations -gt 0 ]]; then
      msg="$msg ($violations action(s) not SHA-pinned)"
    fi
    if [[ $comment_violations -gt 0 ]]; then
      msg="$msg ($comment_violations SHA(s) missing version comment)"
    fi
    fail "$msg"
  fi
}

# ---------------------------------------------------------------------------
# S2: Least-Privilege Permissions
# A permissions: block must exist at top level (before jobs:)
# ---------------------------------------------------------------------------
check_s2() {
  local permissions_line
  permissions_line=$(awk '
    /^jobs:/ { exit }
    /^permissions:/ { print; exit }
  ' "$FILE")
  permissions_line=${permissions_line%%#*}

  if [[ -z "$permissions_line" ]]; then
    fail "S2 -- Least-Privilege Permissions (no top-level permissions: block)"
  elif [[ "$permissions_line" =~ ^permissions:[[:space:]]*write-all([[:space:]]|$) ]]; then
    fail "S2 -- Least-Privilege Permissions (top-level permissions must not use write-all)"
  else
    pass "S2 -- Least-Privilege Permissions"
  fi
}

# ---------------------------------------------------------------------------
# S3: OIDC Authentication (advisory)
# Warn if static cloud credential secrets are used
# ---------------------------------------------------------------------------
check_s3() {
  local static_creds
  static_creds=$(count_matches 'secrets\.(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AZURE_CREDENTIALS|GCP_SA_KEY)' "$FILE")

  if [[ "$static_creds" -gt 0 ]]; then
    advisory "S3 -- OIDC Authentication (static cloud credentials detected; prefer OIDC)"
  else
    pass "S3 -- OIDC Authentication"
  fi
}

# ---------------------------------------------------------------------------
# S4: Injection Prevention
# Check for dangerous github.event context used directly in run: blocks.
# ---------------------------------------------------------------------------
check_s4() {
  local violations

  # Pattern for dangerous event subfields
  local dangerous='github\.event\.(issue\.title|issue\.body|pull_request\.title|pull_request\.body|pull_request\.head\.ref|comment\.body|review\.body|head_commit\.message|commits|pages)'

  violations=$(awk -v pat="$dangerous" '
    BEGIN { in_run = 0; count = 0 }
    # Multi-line run block start
    /^[[:space:]]*-?[[:space:]]*run:[[:space:]]*[>|][+-]?[[:space:]]*$/ {
      in_run = 1
      next
    }
    # Single-line run (not multi-line)
    /^[[:space:]]*-?[[:space:]]*run:[[:space:]]*[^|>]/ {
      if (match($0, "\\$\\{\\{[[:space:]]*" pat)) {
        count++
      }
      next
    }
    in_run == 1 {
      # End of run block: non-indented line or new YAML key at step level
      if ($0 ~ /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_-]*:/ && $0 !~ /^[[:space:]]*#/) {
        in_run = 0
        next
      }
      # Check for empty lines that might signal end of block
      if ($0 ~ /^[[:space:]]*-[[:space:]]+(uses|name|if|env|with|id):/) {
        in_run = 0
        next
      }
      if (match($0, "\\$\\{\\{[[:space:]]*" pat)) {
        count++
      }
    }
    END { print count }
  ' "$FILE")

  if [[ "$violations" -eq 0 ]]; then
    pass "S4 -- Injection Prevention"
  else
    fail "S4 -- Injection Prevention ($violations dangerous interpolation(s) in run: blocks)"
  fi
}

# ---------------------------------------------------------------------------
# E1: Path Filtering (advisory)
# Check if paths: or paths-ignore: appears in the trigger section
# ---------------------------------------------------------------------------
check_e1() {
  local has_paths
  has_paths=$(awk '
    /^jobs:/ { exit }
    /paths:/ { print "found"; exit }
    /paths-ignore:/ { print "found"; exit }
  ' "$FILE")

  if [[ "$has_paths" == "found" ]]; then
    pass "E1 -- Path Filtering"
  else
    advisory "E1 -- Path Filtering (no paths: or paths-ignore: on triggers)"
  fi
}

# ---------------------------------------------------------------------------
# E2: Native Caching
# For each setup-* action, check if cache: appears in the with: block
# ---------------------------------------------------------------------------
check_e2() {
  local result

  result=$(awk '
    BEGIN { in_setup = 0; has_cache = 0; missing = 0; total = 0 }
    /uses:.*setup-(node|python|go|java)/ {
      if (in_setup && !has_cache) { missing++ }
      in_setup = 1
      has_cache = 0
      total++
      next
    }
    in_setup == 1 && /^[[:space:]]*cache:/ {
      has_cache = 1
      next
    }
    in_setup == 1 && /^[[:space:]]*-[[:space:]]/ {
      if (!has_cache) { missing++ }
      in_setup = 0
      has_cache = 0
    }
    END {
      if (in_setup && !has_cache) { missing++ }
      if (total == 0) { print "none" }
      else { print missing }
    }
  ' "$FILE")

  if [[ "$result" == "none" ]]; then
    pass "E2 -- Native Caching (no setup-* actions found)"
  elif [[ "$result" -eq 0 ]]; then
    pass "E2 -- Native Caching"
  else
    fail "E2 -- Native Caching ($result setup-* action(s) missing cache: parameter)"
  fi
}

# ---------------------------------------------------------------------------
# E3: Concurrency Control
# Check for concurrency: at the top level
# ---------------------------------------------------------------------------
check_e3() {
  local status
  status=$(awk '
    function trim_inline_comment(value) {
      sub(/[[:space:]]*#.*$/, "", value)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    BEGIN { found = 0; in_block = 0; has_group = 0; has_cancel = 0 }
    /^jobs:/ { exit }
    /^concurrency:/ {
      found = 1
      line = $0
      sub(/^concurrency:[[:space:]]*/, "", line)
      line = trim_inline_comment(line)
      if (line == "") {
        in_block = 1
        next
      }
      if (line ~ /^\{/) {
        if (line ~ /(^|[,{[:space:]])group[[:space:]]*:/) { has_group = 1 }
        if (line ~ /(^|[,{[:space:]])cancel-in-progress[[:space:]]*:/) { has_cancel = 1 }
      }
      exit
    }
    in_block == 1 {
      if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*#/) { next }
      if ($0 !~ /^[[:space:]]+/) { exit }
      if ($0 ~ /^[[:space:]]+group:/) { has_group = 1 }
      if ($0 ~ /^[[:space:]]+cancel-in-progress:/) { has_cancel = 1 }
    }
    END {
      if (!found) { print "missing" }
      else if (has_group && has_cancel) { print "valid" }
      else if (!has_group && !has_cancel) { print "missing-both" }
      else if (!has_group) { print "missing-group" }
      else { print "missing-cancel" }
    }
  ' "$FILE")

  if [[ "$status" == "valid" ]]; then
    pass "E3 -- Concurrency Control"
  elif [[ "$status" == "missing" ]]; then
    fail "E3 -- Concurrency Control (no top-level concurrency: block)"
  elif [[ "$status" == "missing-group" ]]; then
    fail "E3 -- Concurrency Control (concurrency: block missing group:)"
  elif [[ "$status" == "missing-cancel" ]]; then
    fail "E3 -- Concurrency Control (concurrency: block missing cancel-in-progress:)"
  else
    fail "E3 -- Concurrency Control (concurrency: block missing group: and cancel-in-progress:)"
  fi
}

# ---------------------------------------------------------------------------
# E4: Matrix Optimization (advisory)
# If strategy.matrix is used, check fail-fast is not explicitly set to false
# ---------------------------------------------------------------------------
check_e4() {
  local has_matrix
  has_matrix=$(count_matches 'matrix:' "$FILE")

  if [[ "$has_matrix" -eq 0 ]]; then
    pass "E4 -- Matrix Optimization (no matrix used)"
    return
  fi

  local fail_fast_false
  fail_fast_false=$(count_matches 'fail-fast:[[:space:]]*false' "$FILE")

  if [[ "$fail_fast_false" -gt 0 ]]; then
    advisory "E4 -- Matrix Optimization (fail-fast: false detected)"
  else
    pass "E4 -- Matrix Optimization"
  fi
}

# ---------------------------------------------------------------------------
# Run all checks
# ---------------------------------------------------------------------------
check_s1
check_s2
check_s3
check_s4
check_e1
check_e2
check_e3
check_e4

# ---------------------------------------------------------------------------
# Print results
# ---------------------------------------------------------------------------
echo "## Workflow Validation: $BASENAME"
echo ""
echo "$RESULTS"
echo "**Summary**: $PASS passed, $FAIL failed, $ADVISORY advisory"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
