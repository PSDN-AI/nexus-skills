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

  # --- Required top-level keys ---
  local required_keys=("version:" "domain:" "generated_at:" "generated_from:" "tasks:" "execution_plan:" "validation:")
  for key in "${required_keys[@]}"; do
    if ! grep -q "^${key}" "$tasks_file"; then
      echo "Error: Missing required top-level key: ${key}" >&2
      errors=$((errors + 1))
    fi
  done

  # --- Task-level validation ---
  local task_count
  task_count=$(grep -c '^  - id:' "$tasks_file" 2>/dev/null || echo "0")

  if [[ "$task_count" -eq 0 ]]; then
    echo "Error: No tasks found in tasks.yaml" >&2
    errors=$((errors + 1))
  fi

  # Check required task fields exist somewhere after each task id
  local task_ids=()
  while IFS= read -r line; do
    local tid
    tid=$(echo "$line" | sed 's/^  - id: *//' | tr -d '"' | tr -d "'")
    task_ids+=("$tid")
  done < <(grep '^  - id:' "$tasks_file")

  # Validate task ID format: PREFIX-NNN
  for tid in "${task_ids[@]}"; do
    if ! echo "$tid" | grep -qE '^[A-Z]+-[0-9]+$'; then
      echo "Error: Invalid task ID format: ${tid} (expected PREFIX-NNN)" >&2
      errors=$((errors + 1))
    fi
  done

  # Check required fields per task (not sampling — every task must have every field)
  local required_task_fields=("name:" "depends_on:" "estimated_complexity:" "files_touched:" "acceptance_criteria:" "prompt_context:")
  local tasks_section
  tasks_section=$(sed -n '/^tasks:/,/^execution_plan:/p' "$tasks_file")

  for tid in "${task_ids[@]}"; do
    # Extract block for this task: from "- id: TID" to next "- id:" or end
    local task_block
    task_block=$(echo "$tasks_section" | sed -n "/^  - id: ${tid}/,/^  - id:/p" | sed '$ d')
    # If last task, sed range won't match a closing "- id:", so result is empty
    if [[ -z "$task_block" ]]; then
      task_block=$(echo "$tasks_section" | sed -n "/^  - id: ${tid}/,\$p")
    fi

    for field in "${required_task_fields[@]}"; do
      if ! echo "$task_block" | grep -q "    ${field}"; then
        echo "Error: Task ${tid} missing required field: ${field}" >&2
        errors=$((errors + 1))
      fi
    done
  done

  # Validate estimated_complexity values
  while IFS= read -r line; do
    local complexity
    complexity=$(echo "$line" | sed 's/.*estimated_complexity: *//' | tr -d '"' | tr -d "'")
    case "$complexity" in
      low|medium|high) ;;
      *)
        echo "Error: Invalid complexity value: ${complexity} (expected low|medium|high)" >&2
        errors=$((errors + 1))
        ;;
    esac
  done < <(grep 'estimated_complexity:' "$tasks_file")

  # --- DAG validation (no circular dependencies) ---
  validate_dag "$tasks_file" || errors=$((errors + 1))

  # --- Execution plan validation ---
  local phase_count
  phase_count=$(grep -c '^  - phase:' "$tasks_file" 2>/dev/null || echo "0")

  if [[ "$phase_count" -eq 0 ]]; then
    echo "Error: No execution phases found" >&2
    errors=$((errors + 1))
  fi

  # Build task-to-phase mapping from execution_plan
  # Also detect unknown tasks and duplicates
  local -A task_phase_map=()
  local -A task_seen_count=()
  local current_phase=""
  local exec_section
  exec_section=$(sed -n '/^execution_plan:/,/^validation:/p' "$tasks_file")

  while IFS= read -r line; do
    if echo "$line" | grep -q '  - phase:'; then
      current_phase=$(echo "$line" | sed 's/.*phase: *//' | tr -d '"' | tr -d ' ')
    fi
    if [[ -n "$current_phase" ]] && echo "$line" | grep -qE '^\s+- [A-Z]+-[0-9]+'; then
      local ptid
      ptid=$(echo "$line" | sed 's/.*- //' | tr -d '"' | tr -d "'" | tr -d ' ')
      task_phase_map["$ptid"]="$current_phase"
      task_seen_count["$ptid"]=$(( ${task_seen_count[$ptid]:-0} + 1 ))
    fi
  done <<< "$exec_section"

  # Verify all declared tasks appear in execution plan
  for tid in "${task_ids[@]}"; do
    if [[ -z "${task_phase_map[$tid]:-}" ]]; then
      echo "Error: Task ${tid} not found in execution plan" >&2
      errors=$((errors + 1))
    fi
  done

  # Verify no unknown tasks in execution plan
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

  # Verify no duplicate tasks across phases
  for ptid in "${!task_seen_count[@]}"; do
    if [[ "${task_seen_count[$ptid]}" -gt 1 ]]; then
      echo "Error: Task ${ptid} appears ${task_seen_count[$ptid]} times in execution plan (must appear exactly once)" >&2
      errors=$((errors + 1))
    fi
  done

  # Verify execution plan respects dependency ordering
  validate_phase_ordering "$tasks_file" task_phase_map || errors=$((errors + 1))

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

  # Extract task IDs and their dependencies
  # Simple approach: for each task, verify its depends_on targets exist
  # and there are no cycles via iterative dependency resolution
  local -a all_ids=()
  local -A deps_map=()

  local current_id=""
  local in_depends=false

  while IFS= read -r line; do
    # Detect task ID
    if echo "$line" | grep -q '^  - id:'; then
      current_id=$(echo "$line" | sed 's/^  - id: *//' | tr -d '"' | tr -d "'")
      all_ids+=("$current_id")
      deps_map["$current_id"]=""
      in_depends=false
    fi

    # Detect depends_on section
    if echo "$line" | grep -q '    depends_on:'; then
      in_depends=true
      # Check if it's an inline empty array
      if echo "$line" | grep -q '\[\]'; then
        in_depends=false
      fi
      continue
    fi

    # Collect dependency entries
    if [[ "$in_depends" == "true" ]]; then
      if echo "$line" | grep -qE '^\s+- [A-Z]+-[0-9]+'; then
        local dep
        dep=$(echo "$line" | sed 's/.*- //' | tr -d '"' | tr -d "'" | tr -d ' ')
        if [[ -n "${deps_map[$current_id]:-}" ]]; then
          deps_map["$current_id"]="${deps_map[$current_id]} ${dep}"
        else
          deps_map["$current_id"]="$dep"
        fi
      else
        in_depends=false
      fi
    fi
  done < <(sed -n '/^tasks:/,/^execution_plan:/p' "$tasks_file")

  # Verify all dependency targets exist
  for tid in "${all_ids[@]}"; do
    for dep in ${deps_map[$tid]:-}; do
      local dep_found=false
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

  # Topological sort to detect cycles (Kahn's algorithm)
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
    for node in "${queue[@]}"; do
      resolved=$((resolved + 1))
      # For each task that depends on this node, decrement its in-degree
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

# validate_phase_ordering <tasks_yaml_path> <task_phase_map_nameref>
# Checks that every task's dependencies are in strictly earlier phases.
# Returns 0 if valid, 1 if a dependency violation is found.
validate_phase_ordering() {
  local tasks_file="$1"
  local -n phase_map=$2
  local violations=0

  # Re-extract deps_map from tasks section
  local -a all_ids=()
  local -A deps_map=()
  local current_id=""
  local in_depends=false

  while IFS= read -r line; do
    if echo "$line" | grep -q '^  - id:'; then
      current_id=$(echo "$line" | sed 's/^  - id: *//' | tr -d '"' | tr -d "'")
      all_ids+=("$current_id")
      deps_map["$current_id"]=""
      in_depends=false
    fi

    if echo "$line" | grep -q '    depends_on:'; then
      in_depends=true
      if echo "$line" | grep -q '\[\]'; then
        in_depends=false
      fi
      continue
    fi

    if [[ "$in_depends" == "true" ]]; then
      if echo "$line" | grep -qE '^\s+- [A-Z]+-[0-9]+'; then
        local dep
        dep=$(echo "$line" | sed 's/.*- //' | tr -d '"' | tr -d "'" | tr -d ' ')
        if [[ -n "${deps_map[$current_id]:-}" ]]; then
          deps_map["$current_id"]="${deps_map[$current_id]} ${dep}"
        else
          deps_map["$current_id"]="$dep"
        fi
      else
        in_depends=false
      fi
    fi
  done < <(sed -n '/^tasks:/,/^execution_plan:/p' "$tasks_file")

  # Check: for every task, all its dependencies must be in earlier phases
  for tid in "${all_ids[@]}"; do
    local tid_phase="${phase_map[$tid]:-}"
    [[ -z "$tid_phase" ]] && continue  # already reported as missing from plan

    for dep in ${deps_map[$tid]:-}; do
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
