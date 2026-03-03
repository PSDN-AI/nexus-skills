#!/usr/bin/env bash
# validator.sh — Validate tasks.yaml structure and semantics
# Sourced by plan.sh; not intended for standalone execution.

# validate_tasks_yaml <tasks_yaml_path>
# Returns 0 on success, 2 on structure error.
# Prints validation errors to stderr.
validate_tasks_yaml() {
  local tasks_file="$1"
  local errors=0

  if [[ ! -f "$tasks_file" ]]; then
    echo "Error: tasks.yaml not found: ${tasks_file}" >&2
    return 2
  fi

  if ! command -v yq >/dev/null 2>&1; then
    echo "Error: yq v4+ (mikefarah/yq) is required for validation" >&2
    return 2
  fi

  if ! yq -e '.' "$tasks_file" >/dev/null 2>&1; then
    echo "Error: Invalid YAML syntax in tasks.yaml" >&2
    return 2
  fi

  # --- Required top-level keys ---
  local required_keys=("version" "domain" "generated_at" "generated_from" "tasks" "execution_plan" "validation")
  local key
  for key in "${required_keys[@]}"; do
    if ! yq -e "has(\"${key}\")" "$tasks_file" >/dev/null 2>&1; then
      echo "Error: Missing required top-level key: ${key}:" >&2
      errors=$((errors + 1))
    fi
  done

  # --- generated_from validation ---
  local required_generated_from_fields=("spec" "boundary" "contracts")
  local field
  for field in "${required_generated_from_fields[@]}"; do
    if ! yq -e ".generated_from // {} | has(\"${field}\")" "$tasks_file" >/dev/null 2>&1; then
      echo "Error: generated_from missing required field: ${field}" >&2
      errors=$((errors + 1))
    fi
  done

  local actual_domain
  actual_domain=$(yq -r '.domain // ""' "$tasks_file")
  local generated_spec
  generated_spec=$(yq -r '.generated_from.spec // ""' "$tasks_file")
  local generated_boundary
  generated_boundary=$(yq -r '.generated_from.boundary // ""' "$tasks_file")

  if [[ -n "$actual_domain" ]] && [[ -n "$generated_spec" ]]; then
    local expected_from_spec
    expected_from_spec=$(basename "$(dirname "$generated_spec")")
    if [[ "$actual_domain" != "$expected_from_spec" ]]; then
      echo "Error: domain '${actual_domain}' does not match generated_from.spec directory '${expected_from_spec}'" >&2
      errors=$((errors + 1))
    fi
  fi

  if [[ -n "$actual_domain" ]] && [[ -n "$generated_boundary" ]]; then
    local expected_from_boundary
    expected_from_boundary=$(basename "$(dirname "$generated_boundary")")
    if [[ "$actual_domain" != "$expected_from_boundary" ]]; then
      echo "Error: domain '${actual_domain}' does not match generated_from.boundary directory '${expected_from_boundary}'" >&2
      errors=$((errors + 1))
    fi
  fi

  # --- Task-level validation ---
  local task_count
  task_count=$(yq -r '.tasks // [] | length' "$tasks_file")
  if [[ "$task_count" -eq 0 ]]; then
    echo "Error: No tasks found in tasks.yaml" >&2
    errors=$((errors + 1))
  fi

  local -a task_ids=()
  local i
  for ((i = 0; i < task_count; i++)); do
    local tid
    tid=$(yq -r ".tasks[${i}].id // \"<missing-id-$((i + 1))>\"" "$tasks_file")
    task_ids+=("$tid")

    if ! yq -e ".tasks[${i}] | has(\"id\")" "$tasks_file" >/dev/null 2>&1; then
      echo "Error: Task #$((i + 1)) missing required field: id:" >&2
      errors=$((errors + 1))
    fi

    if [[ "$tid" != "<missing-id-$((i + 1))>" ]] && ! echo "$tid" | grep -qE '^[A-Z]+-[0-9]+$'; then
      echo "Error: Invalid task ID format: ${tid} (expected PREFIX-NNN)" >&2
      errors=$((errors + 1))
    fi

    local required_task_fields=("name" "depends_on" "estimated_complexity" "files_touched" "acceptance_criteria" "prompt_context")
    for field in "${required_task_fields[@]}"; do
      if ! yq -e ".tasks[${i}] | has(\"${field}\")" "$tasks_file" >/dev/null 2>&1; then
        echo "Error: Task ${tid} missing required field: ${field}:" >&2
        errors=$((errors + 1))
      fi
    done

    local complexity
    complexity=$(yq -r ".tasks[${i}].estimated_complexity // \"\"" "$tasks_file")
    case "$complexity" in
      low|medium|high) ;;
      *)
        echo "Error: Invalid complexity value: ${complexity} (expected low|medium|high)" >&2
        errors=$((errors + 1))
        ;;
    esac
  done

  # --- DAG validation (no circular dependencies) ---
  validate_dag "$tasks_file" || errors=$((errors + 1))

  # --- Execution plan validation ---
  local phase_count
  phase_count=$(yq -r '.execution_plan // [] | length' "$tasks_file")
  if [[ "$phase_count" -eq 0 ]]; then
    echo "Error: No execution phases found" >&2
    errors=$((errors + 1))
  fi

  local -A task_phase_map=()
  local -A task_seen_count=()
  local phase_numbers_are_numeric=true
  local expected_phase=1

  for ((i = 0; i < phase_count; i++)); do
    local phase_label="#$((i + 1))"
    local has_phase=false
    if yq -e ".execution_plan[${i}] | has(\"phase\")" "$tasks_file" >/dev/null 2>&1; then
      has_phase=true
      phase_label=$(yq -r ".execution_plan[${i}].phase" "$tasks_file")
    else
      echo "Error: Execution plan phase #$((i + 1)) missing required field: phase" >&2
      errors=$((errors + 1))
      phase_numbers_are_numeric=false
    fi

    if ! yq -e ".execution_plan[${i}] | has(\"tasks\")" "$tasks_file" >/dev/null 2>&1; then
      echo "Error: Execution plan phase ${phase_label} missing required field: tasks" >&2
      errors=$((errors + 1))
    else
      local tasks_len
      tasks_len=$(yq -r ".execution_plan[${i}].tasks // [] | length" "$tasks_file")
      if [[ "$tasks_len" -eq 0 ]]; then
        echo "Error: Execution plan phase ${phase_label} must include at least one task" >&2
        errors=$((errors + 1))
      fi
    fi

    if ! yq -e ".execution_plan[${i}] | has(\"parallel\")" "$tasks_file" >/dev/null 2>&1; then
      echo "Error: Execution plan phase ${phase_label} missing required field: parallel" >&2
      errors=$((errors + 1))
    else
      local parallel_tag
      parallel_tag=$(yq -r ".execution_plan[${i}].parallel | tag" "$tasks_file")
      if [[ "$parallel_tag" != "!!bool" ]]; then
        local parallel_val
        parallel_val=$(yq -r ".execution_plan[${i}].parallel" "$tasks_file")
        echo "Error: Execution plan phase ${phase_label} parallel must be a boolean (found ${parallel_val})" >&2
        errors=$((errors + 1))
      fi
    fi

    if ! yq -e ".execution_plan[${i}] | has(\"reason\")" "$tasks_file" >/dev/null 2>&1; then
      echo "Error: Execution plan phase ${phase_label} missing required field: reason" >&2
      errors=$((errors + 1))
    fi

    if [[ "$has_phase" == "true" ]]; then
      local pnum
      pnum=$(yq -r ".execution_plan[${i}].phase" "$tasks_file")
      if ! echo "$pnum" | grep -qE '^[0-9]+$'; then
        echo "Error: Execution plan phase must be an integer (found ${pnum})" >&2
        errors=$((errors + 1))
        phase_numbers_are_numeric=false
      elif [[ "$pnum" -ne "$expected_phase" ]]; then
        echo "Error: Execution plan phases must be sequential from 1 (expected ${expected_phase}, found ${pnum})" >&2
        errors=$((errors + 1))
        phase_numbers_are_numeric=false
      else
        expected_phase=$((expected_phase + 1))
      fi
    fi

    mapfile -t phase_task_ids < <(yq -r ".execution_plan[${i}].tasks[]?" "$tasks_file")
    local ptid
    for ptid in "${phase_task_ids[@]}"; do
      [[ -z "$ptid" ]] && continue
      if [[ "$has_phase" == "true" ]]; then
        task_phase_map["$ptid"]="$phase_label"
      fi
      task_seen_count["$ptid"]=$(( ${task_seen_count[$ptid]:-0} + 1 ))
    done
  done

  local tid
  for tid in "${task_ids[@]}"; do
    if [[ "$tid" == "<missing-id-"* ]]; then
      continue
    fi
    if [[ -z "${task_phase_map[$tid]:-}" ]]; then
      echo "Error: Task ${tid} not found in execution plan" >&2
      errors=$((errors + 1))
    fi
  done

  local ptid
  for ptid in "${!task_phase_map[@]}"; do
    local known=false
    for tid in "${task_ids[@]}"; do
      if [[ "$tid" == "$ptid" ]]; then
        known=true
        break
      fi
    done
    if [[ "$known" == "false" ]]; then
      echo "Error: Unknown task ${ptid} in execution plan (not declared in tasks)" >&2
      errors=$((errors + 1))
    fi
  done

  for ptid in "${!task_seen_count[@]}"; do
    if [[ "${task_seen_count[$ptid]}" -gt 1 ]]; then
      echo "Error: Task ${ptid} appears ${task_seen_count[$ptid]} times in execution plan (must appear exactly once)" >&2
      errors=$((errors + 1))
    fi
  done

  # --- Validation summary section ---
  local required_validation_fields=(
    "total_tasks"
    "total_phases"
    "parallelizable_tasks"
    "acceptance_criteria_mapped"
    "acceptance_criteria_unmapped"
    "unmapped_criteria"
    "files_conflict_check"
    "spec_coverage"
  )
  for field in "${required_validation_fields[@]}"; do
    if ! yq -e ".validation // {} | has(\"${field}\")" "$tasks_file" >/dev/null 2>&1; then
      echo "Error: Validation section missing required field: ${field}" >&2
      errors=$((errors + 1))
    fi
  done

  # --- Dependency ordering semantics ---
  if [[ "$phase_numbers_are_numeric" == "true" ]]; then
    validate_phase_ordering "$tasks_file" || errors=$((errors + 1))
  fi

  if [[ "$errors" -gt 0 ]]; then
    echo "Validation failed: ${errors} error(s) found" >&2
    return 2
  fi

  return 0
}

# validate_dag <tasks_yaml_path>
# Checks that task dependencies form a DAG (no circular dependencies).
# Returns 0 if valid, 1 if circular dependency detected.
validate_dag() {
  local tasks_file="$1"
  local task_count
  task_count=$(yq -r '.tasks // [] | length' "$tasks_file")

  local -a all_ids=()
  local -A deps_map=()
  local i
  for ((i = 0; i < task_count; i++)); do
    local tid
    tid=$(yq -r ".tasks[${i}].id // \"\"" "$tasks_file")
    [[ -z "$tid" ]] && continue
    all_ids+=("$tid")
    mapfile -t deps < <(TASK_ID="$tid" yq -r '.tasks[] | select(.id == env(TASK_ID)) | .depends_on[]?' "$tasks_file")
    if [[ ${#deps[@]} -gt 0 ]]; then
      deps_map["$tid"]="${deps[*]}"
    else
      deps_map["$tid"]=""
    fi
  done

  local tid dep
  for tid in "${all_ids[@]}"; do
    for dep in ${deps_map[$tid]:-}; do
      local dep_found=false
      local check_id
      for check_id in "${all_ids[@]}"; do
        if [[ "$check_id" == "$dep" ]]; then
          dep_found=true
          break
        fi
      done
      if [[ "$dep_found" == "false" ]]; then
        echo "Error: Task ${tid} depends on unknown task ${dep}" >&2
        return 1
      fi
    done
  done

  local -A in_degree=()
  for tid in "${all_ids[@]}"; do
    in_degree["$tid"]=0
  done
  for tid in "${all_ids[@]}"; do
    for dep in ${deps_map[$tid]:-}; do
      in_degree["$tid"]=$(( ${in_degree[$tid]} + 1 ))
    done
  done

  local -a queue=()
  for tid in "${all_ids[@]}"; do
    if [[ "${in_degree[$tid]}" -eq 0 ]]; then
      queue+=("$tid")
    fi
  done

  local resolved=0
  local -a next_queue=()
  while [[ ${#queue[@]} -gt 0 ]]; do
    next_queue=()
    local node
    for node in "${queue[@]}"; do
      resolved=$((resolved + 1))
      for tid in "${all_ids[@]}"; do
        for dep in ${deps_map[$tid]:-}; do
          if [[ "$dep" == "$node" ]]; then
            in_degree["$tid"]=$(( ${in_degree[$tid]} - 1 ))
            if [[ "${in_degree[$tid]}" -eq 0 ]]; then
              next_queue+=("$tid")
            fi
          fi
        done
      done
    done
    queue=("${next_queue[@]}")
  done

  if [[ "$resolved" -ne "${#all_ids[@]}" ]]; then
    echo "Error: Circular dependency detected in task graph" >&2
    return 1
  fi

  return 0
}

# validate_phase_ordering <tasks_yaml_path>
# Checks that every task's dependencies are in strictly earlier phases.
# Returns 0 if valid, 1 if a dependency violation is found.
validate_phase_ordering() {
  local tasks_file="$1"
  local violations=0
  local phase_count
  phase_count=$(yq -r '.execution_plan // [] | length' "$tasks_file")

  local -A phase_map=()
  local i
  for ((i = 0; i < phase_count; i++)); do
    local phase_num
    phase_num=$(yq -r ".execution_plan[${i}].phase // \"\"" "$tasks_file")
    if ! echo "$phase_num" | grep -qE '^[0-9]+$'; then
      continue
    fi
    mapfile -t phase_task_ids < <(yq -r ".execution_plan[${i}].tasks[]?" "$tasks_file")
    local ptid
    for ptid in "${phase_task_ids[@]}"; do
      [[ -z "$ptid" ]] && continue
      phase_map["$ptid"]="$phase_num"
    done
  done

  local task_count
  task_count=$(yq -r '.tasks // [] | length' "$tasks_file")
  for ((i = 0; i < task_count; i++)); do
    local tid
    tid=$(yq -r ".tasks[${i}].id // \"\"" "$tasks_file")
    [[ -z "$tid" ]] && continue
    local tid_phase="${phase_map[$tid]:-}"
    [[ -z "$tid_phase" ]] && continue

    mapfile -t deps < <(TASK_ID="$tid" yq -r '.tasks[] | select(.id == env(TASK_ID)) | .depends_on[]?' "$tasks_file")
    local dep
    for dep in "${deps[@]}"; do
      local dep_phase="${phase_map[$dep]:-}"
      [[ -z "$dep_phase" ]] && continue
      if [[ "$dep_phase" -ge "$tid_phase" ]]; then
        echo "Error: Task ${tid} (phase ${tid_phase}) depends on ${dep} (phase ${dep_phase}) — dependency must be in an earlier phase" >&2
        violations=$((violations + 1))
      fi
    done
  done

  if [[ "$violations" -gt 0 ]]; then
    return 1
  fi
  return 0
}
