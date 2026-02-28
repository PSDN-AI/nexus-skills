#!/usr/bin/env bash
# check_compliance.sh — Legal & Compliance dimension: license, internal references
# Output format: SEVERITY|CHECK|FILE|LINE|DESCRIPTION|REMEDIATION
set -euo pipefail

REPO_PATH="${1:?Usage: check_compliance.sh <repo_path>}"

emit() {
  echo "$1|$2|$3|$4|$5|$6"
}

# --- LICENSE specifies a recognized license ---
license_file=""
for name in LICENSE LICENSE.md LICENSE.txt LICENCE LICENCE.md COPYING; do
  if [[ -f "$REPO_PATH/$name" ]]; then
    license_file="$REPO_PATH/$name"
    break
  fi
done

if [[ -n "$license_file" ]]; then
  content=$(head -20 "$license_file")
  recognized=false
  # Check against common SPDX identifiers
  for license_name in "MIT" "Apache License" "GNU General Public" "BSD" "ISC" "Mozilla Public" "Eclipse Public" "Unlicense" "Creative Commons" "LGPL" "AGPL" "Artistic License" "Boost Software"; do
    if echo "$content" | grep -qi "$license_name"; then
      recognized=true
      break
    fi
  done
  if [[ "$recognized" == "false" ]]; then
    emit "HIGH" "license_unrecognized" "$license_file" "-" "LICENSE file does not match a recognized open-source license" "Use a standard SPDX license (MIT, Apache-2.0, GPL-3.0, etc.)"
  fi
else
  emit "HIGH" "license_missing" "$REPO_PATH" "-" "No LICENSE file found" "Add a LICENSE file with a recognized open-source license"
fi

# --- Internal/company references (configurable keywords) ---
# Default internal keywords — extend via SCAN_INTERNAL_KEYWORDS env var
default_keywords="internal-only|company-confidential|do-not-distribute|proprietary"
extra_keywords="${SCAN_INTERNAL_KEYWORDS:-}"
if [[ -n "$extra_keywords" ]]; then
  keywords="${default_keywords}|${extra_keywords}"
else
  keywords="$default_keywords"
fi

while IFS= read -r result; do
  f=$(echo "$result" | cut -d: -f1)
  ln=$(echo "$result" | cut -d: -f2)
  snippet=$(echo "$result" | cut -d: -f3- | head -c 100)
  emit "HIGH" "internal_reference" "$f" "$ln" "Internal/confidential reference found: ${snippet}" "Remove internal references before making repo public"
done < <(grep -rnEi "$keywords" "$REPO_PATH" \
  --include='*.md' --include='*.txt' --include='*.yml' --include='*.yaml' \
  --include='*.json' --include='*.toml' --include='*.cfg' --include='*.conf' \
  --include='*.ini' --include='*.sh' --include='*.py' --include='*.js' \
  --include='*.ts' --include='*.go' --include='*.rb' --include='*.java' \
  --include='*.rs' \
  --exclude-dir='.git' --exclude-dir='.claude' \
  2>/dev/null | grep -v '/repo-audit/scripts/' || true)

# --- Copyright headers (informational) ---
# Sample up to 20 source files and check for copyright headers
file_count=0
missing_count=0
while IFS= read -r f; do
  file_count=$((file_count + 1))
  head_content=$(head -5 "$f" 2>/dev/null || true)
  if ! echo "$head_content" | grep -qiE '(copyright|©|license|spdx)'; then
    missing_count=$((missing_count + 1))
  fi
  [[ "$file_count" -ge 20 ]] && break
done < <(find "$REPO_PATH" -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.go' -o -name '*.java' -o -name '*.rb' -o -name '*.rs' -o -name '*.c' -o -name '*.cpp' \) -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null || true)

if [[ "$file_count" -gt 0 && "$missing_count" -gt 0 ]]; then
  pct=$((missing_count * 100 / file_count))
  if [[ "$pct" -gt 50 ]]; then
    emit "LOW" "copyright_headers" "$REPO_PATH" "-" "${missing_count}/${file_count} sampled source files lack copyright headers (${pct}%)" "Consider adding copyright/license headers to source files"
  fi
fi

exit 0
