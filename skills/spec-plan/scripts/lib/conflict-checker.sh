#!/usr/bin/env bash
# conflict-checker.sh — Detect files_touched overlaps in parallel phases
# Sourced by plan.sh; not intended for standalone execution.

# paths_conflict <path_a> <path_b>
# Returns 0 if two paths overlap: exact match, or one is a directory
# prefix of the other (directory entries end with /).
paths_conflict() {
  local a="$1" b="$2"
  # Exact match
  [[ "$a" == "$b" ]] && return 0
  # a is a directory that contains b
  if [[ "$a" == */ ]] && [[ "$b" == "$a"* ]]; then return 0; fi
  # b is a directory that contains a
  if [[ "$b" == */ ]] && [[ "$a" == "$b"* ]]; then return 0; fi
  return 1
}

# check_file_conflicts <tasks_yaml_path>
# Returns 0 if no conflicts, 3 if overlapping files in parallel phases.
check_file_conflicts() {
  local tasks_file="$1"
  local conflicts=0

  if ! command -v yq >/dev/null 2>&1; then
    echo "Error: yq v4+ (mikefarah/yq) is required for conflict checks" >&2
    return 3
  fi

  local phase_count
  phase_count=$(yq -r '.execution_plan // [] | length' "$tasks_file")

  local idx
  for ((idx = 0; idx < phase_count; idx++)); do
    local parallel_flag
    parallel_flag=$(yq -r ".execution_plan[${idx}].parallel // false" "$tasks_file")
    [[ "$parallel_flag" != "true" ]] && continue

    local phase_num
    phase_num=$(yq -r ".execution_plan[${idx}].phase // \"?\"" "$tasks_file")

    local -a tids=()
    mapfile -t tids < <(yq -r ".execution_plan[${idx}].tasks[]?" "$tasks_file")
    [[ ${#tids[@]} -le 1 ]] && continue

    check_phase_conflicts "$tasks_file" "$phase_num" "${tids[@]}" || conflicts=$((conflicts + 1))
  done

  if [[ "$conflicts" -gt 0 ]]; then
    return 3
  fi

  return 0
}

# check_phase_conflicts <tasks_yaml_path> <phase_number> <task_id...>
# Checks for file overlap among tasks in a single parallel phase.
# Returns 0 if clean, 1 if overlap found.
check_phase_conflicts() {
  local tasks_file="$1"
  local phase_num="$2"
  shift 2
  local -a task_ids=("$@")

  # Collect files_touched per task
  local -A task_files=()
  for tid in "${task_ids[@]}"; do
    task_files["$tid"]=$(extract_files_touched "$tasks_file" "$tid")
  done

  # Compare each pair of tasks for overlap
  local i j
  for ((i = 0; i < ${#task_ids[@]}; i++)); do
    for ((j = i + 1; j < ${#task_ids[@]}; j++)); do
      local tid_a="${task_ids[$i]}"
      local tid_b="${task_ids[$j]}"
      local files_a="${task_files[$tid_a]}"
      local files_b="${task_files[$tid_b]}"

      # Find conflicts: exact match OR directory containment
      local -a conflicts_found=()
      local fa fb
      while IFS= read -r fa; do
        [[ -z "$fa" ]] && continue
        while IFS= read -r fb; do
          [[ -z "$fb" ]] && continue
          if paths_conflict "$fa" "$fb"; then
            conflicts_found+=("${fa} <-> ${fb}")
          fi
        done <<< "$files_b"
      done <<< "$files_a"

      if [[ ${#conflicts_found[@]} -gt 0 ]]; then
        echo "Error: files_touched conflict in phase ${phase_num}:" >&2
        echo "  Tasks ${tid_a} and ${tid_b} share files:" >&2
        for conflict in "${conflicts_found[@]}"; do
          echo "    - ${conflict}" >&2
        done
        return 1
      fi
    done
  done

  return 0
}

# extract_files_touched <tasks_yaml_path> <task_id>
# Outputs newline-delimited list of files for the given task.
extract_files_touched() {
  local tasks_file="$1"
  local target_id="$2"
  TASK_ID="$target_id" yq -r '.tasks[] | select(.id == env(TASK_ID)) | .files_touched[]?' "$tasks_file"
}
