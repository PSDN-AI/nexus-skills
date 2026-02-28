#!/usr/bin/env bash
# check_repo_hygiene.sh — Repo Hygiene dimension: large files, build artifacts, logs
# Output format: SEVERITY|CHECK|FILE|LINE|DESCRIPTION|REMEDIATION
set -euo pipefail

REPO_PATH="${1:?Usage: check_repo_hygiene.sh <repo_path>}"

emit() {
  echo "$1|$2|$3|$4|$5|$6"
}

# --- Large binary files (>10MB) ---
while IFS= read -r f; do
  size_bytes=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo "0")
  size_mb=$((size_bytes / 1048576))
  emit "MEDIUM" "large_file" "$f" "-" "Large file detected (${size_mb}MB)" "Remove or use Git LFS for large files"
done < <(find "$REPO_PATH" -type f -size +10485760c -not -path '*/.git/*' 2>/dev/null || true)

# --- Log files ---
while IFS= read -r f; do
  emit "MEDIUM" "log_file" "$f" "-" "Log file committed to repository" "Remove log files and add *.log to .gitignore"
done < <(find "$REPO_PATH" -type f \( -name '*.log' -o -name '*.log.*' \) -not -path '*/.git/*' 2>/dev/null || true)

# --- Data dumps / database exports ---
while IFS= read -r f; do
  emit "HIGH" "data_dump" "$f" "-" "Potential data dump or database export found" "Remove data files — they may contain sensitive information"
done < <(find "$REPO_PATH" -type f \( -name '*.sql' -o -name '*.dump' -o -name '*.bak' -o -name '*.csv' -o -name '*.sqlite' -o -name '*.db' \) -size +1048576c -not -path '*/.git/*' -not -path '*/migrations/*' 2>/dev/null || true)

# --- Build artifacts ---
build_dirs=("node_modules" "dist" "__pycache__" ".pytest_cache" ".next" ".nuxt" "build" "target" "vendor/bundle" ".gradle" "bin" "obj")
for dir_name in "${build_dirs[@]}"; do
  while IFS= read -r d; do
    emit "MEDIUM" "build_artifact" "$d" "-" "Build artifact directory found: ${dir_name}" "Remove and add ${dir_name}/ to .gitignore"
  done < <(find "$REPO_PATH" -type d -name "$dir_name" -not -path '*/.git/*' 2>/dev/null || true)
done

# --- .DS_Store / Thumbs.db ---
while IFS= read -r f; do
  emit "LOW" "os_artifact" "$f" "-" "OS-generated file committed" "Remove and add to .gitignore"
done < <(find "$REPO_PATH" -type f \( -name '.DS_Store' -o -name 'Thumbs.db' -o -name 'desktop.ini' \) -not -path '*/.git/*' 2>/dev/null || true)

# --- Directory depth check (>8 levels) ---
max_depth=0
while IFS= read -r d; do
  # Count path components relative to repo root
  rel="${d#"$REPO_PATH"}"
  depth=$(echo "$rel" | tr '/' '\n' | grep -c . || true)
  if [[ "$depth" -gt "$max_depth" ]]; then
    max_depth=$depth
  fi
  if [[ "$depth" -gt 8 ]]; then
    emit "LOW" "deep_directory" "$d" "-" "Directory nesting depth is ${depth} levels (>8)" "Consider flattening directory structure"
    break  # Report only once
  fi
done < <(find "$REPO_PATH" -type d -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | sort -r || true)

exit 0
