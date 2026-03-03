#!/usr/bin/env bash
# coverage.sh — Check acceptance criteria mapping coverage
# Sourced by plan.sh; not intended for standalone execution.

# check_ac_coverage <tasks_yaml_path> <boundary_yaml_path>
# Returns 0 if all P0 ACs are mapped, 4 if P0 ACs are unmapped.
# Prints coverage report to stdout, errors to stderr.
check_ac_coverage() {
  local tasks_file="$1"
  local boundary_file="$2"

  if [[ ! -f "$boundary_file" ]]; then
    echo "Warning: boundary.yaml not found, skipping AC coverage check" >&2
    return 0
  fi

  # Extract all AC IDs from boundary.yaml
  local -a all_ac_ids=()
  local -A ac_priorities=()
  local current_id=""

  while IFS= read -r line; do
    if echo "$line" | grep -q '  - id:'; then
      current_id=$(echo "$line" | sed 's/.*id: *//' | tr -d '"' | tr -d "'")
      all_ac_ids+=("$current_id")
    fi
    if [[ -n "$current_id" ]] && echo "$line" | grep -q '    priority:'; then
      local priority
      priority=$(echo "$line" | sed 's/.*priority: *//' | tr -d '"' | tr -d "'" | tr -d ' ')
      ac_priorities["$current_id"]="$priority"
    fi
  done < "$boundary_file"

  if [[ ${#all_ac_ids[@]} -eq 0 ]]; then
    echo "Warning: No acceptance criteria found in boundary.yaml" >&2
    return 0
  fi

  # Extract all mapped AC IDs from tasks.yaml
  local -a mapped_ac_ids=()
  while IFS= read -r line; do
    local ac_id
    ac_id=$(echo "$line" | sed 's/.*- //' | tr -d '"' | tr -d "'" | tr -d ' ')
    if echo "$ac_id" | grep -qE '^AC-[0-9]+$'; then
      mapped_ac_ids+=("$ac_id")
    fi
  done < <(grep -E '^\s+- AC-[0-9]+' "$tasks_file" 2>/dev/null)

  # Find unmapped ACs
  local -a unmapped=()
  local -a unmapped_p0=()
  local mapped_count=0

  for ac_id in "${all_ac_ids[@]}"; do
    local found=false
    for mapped in "${mapped_ac_ids[@]}"; do
      if [[ "$mapped" == "$ac_id" ]]; then
        found=true
        break
      fi
    done
    if [[ "$found" == "true" ]]; then
      mapped_count=$((mapped_count + 1))
    else
      unmapped+=("$ac_id")
      if [[ "${ac_priorities[$ac_id]:-}" == "P0" ]]; then
        unmapped_p0+=("$ac_id")
      fi
    fi
  done

  local total=${#all_ac_ids[@]}
  local coverage_pct=0
  if [[ "$total" -gt 0 ]]; then
    coverage_pct=$(( mapped_count * 100 / total ))
  fi

  # Report
  echo "AC Coverage: ${mapped_count}/${total} (${coverage_pct}%)"

  if [[ ${#unmapped[@]} -gt 0 ]]; then
    echo "Unmapped ACs:"
    for ac_id in "${unmapped[@]}"; do
      local priority="${ac_priorities[$ac_id]:-unknown}"
      echo "  - ${ac_id} (${priority})"
    done
  fi

  # Fail if any P0 ACs are unmapped
  if [[ ${#unmapped_p0[@]} -gt 0 ]]; then
    echo "Error: ${#unmapped_p0[@]} P0 acceptance criteria unmapped:" >&2
    for ac_id in "${unmapped_p0[@]}"; do
      echo "  - ${ac_id}" >&2
    done
    return 4
  fi

  return 0
}
