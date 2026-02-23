#!/usr/bin/env bash
# check_documentation.sh — Documentation dimension: README, LICENSE, CONTRIBUTING, etc.
# Output format: SEVERITY|CHECK|FILE|LINE|DESCRIPTION|REMEDIATION
set -euo pipefail

REPO_PATH="${1:?Usage: check_documentation.sh <repo_path>}"

emit() {
  echo "$1|$2|$3|$4|$5|$6"
}

# --- README.md exists and has substance ---
readme=""
for name in README.md README.rst README.txt README; do
  if [[ -f "$REPO_PATH/$name" ]]; then
    readme="$REPO_PATH/$name"
    break
  fi
done

if [[ -z "$readme" ]]; then
  emit "HIGH" "readme_missing" "$REPO_PATH" "-" "No README file found" "Create a README.md with project overview, quick start, and usage"
else
  char_count=$(wc -c < "$readme" | tr -d ' ')
  line_count=$(wc -l < "$readme" | tr -d ' ')
  if [[ "$char_count" -lt 500 && "$line_count" -lt 50 ]]; then
    emit "HIGH" "readme_thin" "$readme" "-" "README exists but is too brief (${char_count} chars, ${line_count} lines)" "Expand README with description, quick start, usage examples"
  fi
fi

# --- LICENSE file exists ---
license_file=""
for name in LICENSE LICENSE.md LICENSE.txt LICENCE LICENCE.md COPYING; do
  if [[ -f "$REPO_PATH/$name" ]]; then
    license_file="$REPO_PATH/$name"
    break
  fi
done

if [[ -z "$license_file" ]]; then
  emit "HIGH" "license_missing" "$REPO_PATH" "-" "No LICENSE file found" "Add a LICENSE file (e.g., MIT, Apache-2.0)"
fi

# --- CONTRIBUTING.md exists ---
if [[ ! -f "$REPO_PATH/CONTRIBUTING.md" ]]; then
  emit "MEDIUM" "contributing_missing" "$REPO_PATH" "-" "No CONTRIBUTING.md found" "Add CONTRIBUTING.md with contribution guidelines"
fi

# --- .gitignore exists ---
if [[ ! -f "$REPO_PATH/.gitignore" ]]; then
  emit "MEDIUM" "gitignore_missing" "$REPO_PATH" "-" "No .gitignore file found" "Add .gitignore appropriate for your project language"
fi

# --- Code of Conduct ---
coc=""
for name in CODE_OF_CONDUCT.md CODE_OF_CONDUCT.txt .github/CODE_OF_CONDUCT.md; do
  if [[ -f "$REPO_PATH/$name" ]]; then
    coc="$REPO_PATH/$name"
    break
  fi
done

if [[ -z "$coc" ]]; then
  emit "LOW" "coc_missing" "$REPO_PATH" "-" "No Code of Conduct found" "Consider adding CODE_OF_CONDUCT.md (e.g., Contributor Covenant)"
fi

exit 0
