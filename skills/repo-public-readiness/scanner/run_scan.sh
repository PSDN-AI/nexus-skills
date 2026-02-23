#!/usr/bin/env bash
# run_scan.sh — Main entry point for Repo Public Readiness Scanner
# Usage: run_scan.sh <repo_path>
# Output: Markdown report to stdout
set -euo pipefail

# Require bash 4+ (associative arrays, modern features)
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "Error: bash 4.0+ required (found ${BASH_VERSION})." >&2
  echo "  macOS: brew install bash" >&2
  echo "  Linux: sudo apt-get install bash" >&2
  exit 1
fi

REPO_PATH="${1:?Usage: run_scan.sh <repo_path>}"
REPO_PATH=$(cd "$REPO_PATH" && pwd)  # Resolve to absolute path
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCAN_DATE=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
REPO_NAME=$(basename "$REPO_PATH")

# --- Temporary files for findings ---
TMPDIR_SCAN=$(mktemp -d)
trap 'rm -rf "$TMPDIR_SCAN"' EXIT

# --- Run all check modules ---
declare -A DIMENSION_NAMES=(
  [secrets]="Security"
  [code_quality]="Code Quality"
  [documentation]="Documentation"
  [repo_hygiene]="Repo Hygiene"
  [compliance]="Legal/Compliance"
)

declare -A DIMENSION_SCRIPTS=(
  [secrets]="check_secrets.sh"
  [code_quality]="check_code_quality.sh"
  [documentation]="check_documentation.sh"
  [repo_hygiene]="check_repo_hygiene.sh"
  [compliance]="check_compliance.sh"
)

DIMENSIONS=(secrets code_quality documentation repo_hygiene compliance)

for dim in "${DIMENSIONS[@]}"; do
  script="${SCRIPT_DIR}/${DIMENSION_SCRIPTS[$dim]}"
  if [[ -x "$script" ]]; then
    exit_code=0
    bash "$script" "$REPO_PATH" > "$TMPDIR_SCAN/${dim}.txt" 2>"$TMPDIR_SCAN/${dim}.err" || exit_code=$?
    if [[ "$exit_code" -ne 0 ]]; then
      err_msg=$(head -1 "$TMPDIR_SCAN/${dim}.err" 2>/dev/null | head -c 120)
      echo "HIGH|${dim}_script_error|-|-|${DIMENSION_NAMES[$dim]} check failed (exit ${exit_code}): ${err_msg}|Investigate and fix ${DIMENSION_SCRIPTS[$dim]}" >> "$TMPDIR_SCAN/${dim}.txt"
    fi
  else
    echo "SKIPPED|${dim}|-|-|Script not found or not executable: ${DIMENSION_SCRIPTS[$dim]}|-" > "$TMPDIR_SCAN/${dim}.txt"
  fi
done

# --- Count findings per dimension ---
count_severity() {
  local file="$1" severity="$2"
  local count
  count=$(grep -c "^${severity}|" "$file" 2>/dev/null || true)
  echo "${count:-0}" | tr -d '[:space:]'
}

# --- Determine overall status ---
overall_has_critical=false
overall_has_high=false

for dim in "${DIMENSIONS[@]}"; do
  f="$TMPDIR_SCAN/${dim}.txt"
  crit=$(count_severity "$f" "CRITICAL")
  high=$(count_severity "$f" "HIGH")
  [[ "$crit" -gt 0 ]] && overall_has_critical=true
  [[ "$high" -gt 0 ]] && overall_has_high=true
done

if [[ "$overall_has_critical" == "true" ]]; then
  OVERALL_STATUS="❌ NOT READY"
elif [[ "$overall_has_high" == "true" ]]; then
  OVERALL_STATUS="⚠️ NEEDS WORK"
else
  OVERALL_STATUS="✅ READY"
fi

# --- Generate Report ---
cat <<EOF
# Repo Public Readiness Report

**Repository**: ${REPO_NAME}
**Scan Date**: ${SCAN_DATE}
**Overall Status**: ${OVERALL_STATUS}

## Summary

| Dimension | Status | Critical | High | Medium | Low | Skipped |
|-----------|--------|----------|------|--------|-----|---------|
EOF

for dim in "${DIMENSIONS[@]}"; do
  f="$TMPDIR_SCAN/${dim}.txt"
  crit=$(count_severity "$f" "CRITICAL")
  high=$(count_severity "$f" "HIGH")
  med=$(count_severity "$f" "MEDIUM")
  low=$(count_severity "$f" "LOW")
  skipped=$(count_severity "$f" "SKIPPED")

  if [[ "$crit" -gt 0 ]]; then
    status="❌"
  elif [[ "$high" -gt 0 ]]; then
    status="⚠️"
  else
    status="✅"
  fi

  echo "| ${DIMENSION_NAMES[$dim]} | ${status} | ${crit} | ${high} | ${med} | ${low} | ${skipped} |"
done

cat <<'EOF'

## Verdict

- Any CRITICAL finding → ❌ NOT READY (block public release)
- Any HIGH finding → ⚠️ NEEDS WORK (strongly recommend fixing)
- Only MEDIUM/LOW → ✅ READY (with recommendations)

## Detailed Findings
EOF

# --- Dimension icons ---
declare -A DIMENSION_ICONS=(
  [secrets]="🔒"
  [code_quality]="📊"
  [documentation]="📝"
  [repo_hygiene]="🧹"
  [compliance]="⚖️"
)

for dim in "${DIMENSIONS[@]}"; do
  f="$TMPDIR_SCAN/${dim}.txt"
  icon="${DIMENSION_ICONS[$dim]}"
  name="${DIMENSION_NAMES[$dim]}"

  echo ""
  echo "### ${icon} ${name}"
  echo ""

  if [[ ! -s "$f" ]]; then
    echo "No findings — all checks passed."
    continue
  fi

  # Check if only skipped
  total_lines=$(wc -l < "$f" | tr -d ' ')
  skipped_lines=$(grep -c "^SKIPPED|" "$f" 2>/dev/null || echo "0")

  has_findings=false

  while IFS='|' read -r severity _check file line desc remediation; do
    if [[ "$severity" == "SKIPPED" ]]; then
      echo "- ⏭️ **SKIPPED**: ${desc} — ${remediation}"
    else
      has_findings=true
      sev_icon="ℹ️"
      case "$severity" in
        CRITICAL) sev_icon="🚨" ;;
        HIGH)     sev_icon="🔴" ;;
        MEDIUM)   sev_icon="🟡" ;;
        LOW)      sev_icon="🔵" ;;
      esac
      file_display="${file#"$REPO_PATH"/}"
      line_display=""
      [[ "$line" != "-" ]] && line_display=":${line}"
      echo "- ${sev_icon} **${severity}** \`${file_display}${line_display}\`: ${desc}"
      echo "  - Remediation: ${remediation}"
    fi
  done < "$f"

  if [[ "$has_findings" == "false" && "$skipped_lines" -lt "$total_lines" ]]; then
    echo "No findings — all checks passed."
  fi
done

# --- Recommended Actions ---
echo ""
echo "## Recommended Actions"
echo ""

action_num=0
for severity in CRITICAL HIGH MEDIUM LOW; do
  for dim in "${DIMENSIONS[@]}"; do
    f="$TMPDIR_SCAN/${dim}.txt"
    while IFS='|' read -r sev _check file line desc remediation; do
      [[ "$sev" != "$severity" ]] && continue
      action_num=$((action_num + 1))
      file_display="${file#"$REPO_PATH"/}"
      echo "${action_num}. **[${sev}]** ${remediation} (\`${file_display}\`)"
    done < "$f"
  done
done

if [[ "$action_num" -eq 0 ]]; then
  echo "No actions required — repository is clean."
fi

echo ""
echo "---"
echo "*Generated by [Repo Public Readiness Scanner](https://github.com/PSDN-AI/nexus-skills)*"
