#!/usr/bin/env bash
# coverage.sh — Check acceptance criteria mapping coverage
# Sourced by plan.sh; not intended for standalone execution.

# check_ac_coverage <tasks_yaml_path> <boundary_yaml_path>
# Returns 0 if all P0 ACs are mapped, 4 if P0 ACs are unmapped.
# Prints coverage report to stdout, errors to stderr.
check_ac_coverage() {
  local tasks_file="$1"
  local boundary_file="$2"

  if ! command -v yq >/dev/null 2>&1; then
    echo "Error: yq v4+ (mikefarah/yq) is required for AC coverage checks" >&2
    return 1
  fi

  if [[ ! -f "$boundary_file" ]]; then
    echo "Warning: boundary.yaml not found, skipping AC coverage check" >&2
    return 0
  fi

  local -a all_ac_ids=()
  local -A ac_priorities=()
  local -a boundary_ac_rows=()
  mapfile -t boundary_ac_rows < <(yq -r '.acceptance_criteria[]? | [.id, (.priority // "unknown")] | @tsv' "$boundary_file")

  local row ac_id priority
  for row in "${boundary_ac_rows[@]}"; do
    ac_id=${row%%$'\t'*}
    priority=${row#*$'\t'}
    [[ -z "$ac_id" ]] && continue
    all_ac_ids+=("$ac_id")
    ac_priorities["$ac_id"]="$priority"
  done

  if [[ ${#all_ac_ids[@]} -eq 0 ]]; then
    echo "Warning: No acceptance criteria found in boundary.yaml" >&2
    return 0
  fi

  local -a mapped_ac_ids=()
  mapfile -t mapped_ac_ids < <(yq -r '.tasks[]?.acceptance_criteria[]?' "$tasks_file")

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
      echo "  - ${ac_id} (${ac_priorities[$ac_id]:-unknown})"
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
