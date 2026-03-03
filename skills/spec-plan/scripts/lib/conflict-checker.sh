#!/usr/bin/env bash
# conflict-checker.sh — Detect files_touched overlaps in parallel phases
# Sourced by plan.sh; not intended for standalone execution.

# check_file_conflicts <tasks_yaml_path>
# Returns 0 if no conflicts, 3 if overlapping files in parallel phases.
check_file_conflicts() {
  local tasks_file="$1"
  local conflicts=0

  # Two-pass approach: first collect parallel phases, then check conflicts.
  # This avoids reading the same file in nested loops (SC2094).

  # --- Pass 1: Collect parallel phases and their task IDs ---
  local -a parallel_phases=()
  local -a parallel_tasks_list=()
  local current_phase=""
  local is_parallel=false
  local -a phase_tasks=()
  local in_exec_plan=false

  local exec_section
  exec_section=$(sed -n '/^execution_plan:/,/^validation:/p' "$tasks_file")

  while IFS= read -r line; do
    if [[ "$line" == "execution_plan:" ]]; then
      in_exec_plan=true
      continue
    fi

    if [[ "$line" == "validation:" ]]; then
      break
    fi

    [[ "$in_exec_plan" != "true" ]] && continue

    # Detect new phase
    if echo "$line" | grep -q '  - phase:'; then
      # Save previous phase if parallel with multiple tasks
      if [[ "$is_parallel" == "true" ]] && [[ ${#phase_tasks[@]} -gt 1 ]]; then
        parallel_phases+=("$current_phase")
        parallel_tasks_list+=("${phase_tasks[*]}")
      fi
      current_phase=$(echo "$line" | sed 's/.*phase: *//' | tr -d '"')
      is_parallel=false
      phase_tasks=()
      continue
    fi

    # Detect parallel flag
    if echo "$line" | grep -q '    parallel:'; then
      local val
      val=$(echo "$line" | sed 's/.*parallel: *//' | tr -d '"' | tr -d ' ')
      [[ "$val" == "true" ]] && is_parallel=true
      continue
    fi

    # Collect task IDs
    if echo "$line" | grep -qE '^\s+- [A-Z]+-[0-9]+'; then
      local tid
      tid=$(echo "$line" | sed 's/.*- //' | tr -d '"' | tr -d "'" | tr -d ' ')
      phase_tasks+=("$tid")
    fi
  done <<< "$exec_section"

  # Handle last phase
  if [[ "$is_parallel" == "true" ]] && [[ ${#phase_tasks[@]} -gt 1 ]]; then
    parallel_phases+=("$current_phase")
    parallel_tasks_list+=("${phase_tasks[*]}")
  fi

  # --- Pass 2: Check conflicts for each parallel phase ---
  local idx
  for ((idx = 0; idx < ${#parallel_phases[@]}; idx++)); do
    local phase_num="${parallel_phases[$idx]}"
    local task_str="${parallel_tasks_list[$idx]}"
    local -a tids=()
    read -ra tids <<< "$task_str"

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

      # Find intersection
      local overlap
      overlap=$(comm -12 \
        <(echo "$files_a" | tr ' ' '\n' | sort) \
        <(echo "$files_b" | tr ' ' '\n' | sort) 2>/dev/null)

      if [[ -n "$overlap" ]]; then
        echo "Error: files_touched conflict in phase ${phase_num}:" >&2
        echo "  Tasks ${tid_a} and ${tid_b} share files:" >&2
        echo "$overlap" | while IFS= read -r f; do
          echo "    - ${f}" >&2
        done
        return 1
      fi
    done
  done

  return 0
}

# extract_files_touched <tasks_yaml_path> <task_id>
# Outputs space-separated list of files for the given task.
extract_files_touched() {
  local tasks_file="$1"
  local target_id="$2"
  local in_task=false
  local in_files=false
  local files=""

  local tasks_section
  tasks_section=$(sed -n '/^tasks:/,/^execution_plan:/p' "$tasks_file")

  while IFS= read -r line; do
    # Find the target task
    if echo "$line" | grep -q "^  - id: ${target_id}"; then
      in_task=true
      continue
    fi

    # Stop at next task
    if [[ "$in_task" == "true" ]] && echo "$line" | grep -q '^  - id:'; then
      break
    fi

    [[ "$in_task" != "true" ]] && continue

    # Detect files_touched section
    if echo "$line" | grep -q '    files_touched:'; then
      in_files=true
      if echo "$line" | grep -q '\[\]'; then
        in_files=false
      fi
      continue
    fi

    # Collect file entries
    if [[ "$in_files" == "true" ]]; then
      if echo "$line" | grep -qE '^\s+- "'; then
        local f
        f=$(echo "$line" | sed 's/.*- "//' | sed 's/".*//')
        files="${files} ${f}"
      elif echo "$line" | grep -qE "^\s+- '"; then
        local f
        f=$(echo "$line" | sed "s/.*- '//" | sed "s/'.*//")
        files="${files} ${f}"
      elif echo "$line" | grep -qE '^\s+- [^[]'; then
        local f
        f=$(echo "$line" | sed 's/.*- //' | tr -d '"' | tr -d "'" | tr -d ' ')
        files="${files} ${f}"
      else
        in_files=false
      fi
    fi
  done <<< "$tasks_section"

  echo "$files"
}
