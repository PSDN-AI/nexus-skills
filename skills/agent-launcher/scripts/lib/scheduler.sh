#!/usr/bin/env bash
# scheduler.sh — Build ready queue from DAG and execution phases
# Sourced by launch.sh; not intended for standalone execution.

# get_all_task_ids <tasks_yaml>
# Outputs one task ID per line.
get_all_task_ids() {
  local tasks_file="$1"
  grep '^  - id:' "$tasks_file" | sed 's/^  - id: *//' | tr -d '"' | tr -d "'"
}

# get_task_deps <tasks_yaml> <task_id>
# Outputs space-separated dependency IDs for a task. Empty string if none.
get_task_deps() {
  local tasks_file="$1"
  local target_id="$2"
  local in_task=false
  local in_deps=false
  local deps=""

  local tasks_section
  tasks_section=$(sed -n '/^tasks:/,/^execution_plan:/p' "$tasks_file")

  while IFS= read -r line; do
    if echo "$line" | grep -q "^  - id: ${target_id}"; then
      in_task=true
      continue
    fi
    if [[ "$in_task" == "true" ]] && echo "$line" | grep -q '^  - id:'; then
      break
    fi
    [[ "$in_task" != "true" ]] && continue

    if echo "$line" | grep -q '    depends_on:'; then
      in_deps=true
      if echo "$line" | grep -q '\[\]'; then
        in_deps=false
      fi
      continue
    fi

    if [[ "$in_deps" == "true" ]]; then
      if echo "$line" | grep -qE '^\s+- [A-Z]+-[0-9]+'; then
        local dep
        dep=$(echo "$line" | sed 's/.*- //' | tr -d '"' | tr -d "'" | tr -d ' ')
        deps="${deps} ${dep}"
      else
        in_deps=false
      fi
    fi
  done <<< "$tasks_section"

  echo "$deps" | xargs
}

# get_task_field <tasks_yaml> <task_id> <field_name>
# Outputs the value of a simple scalar field for a task.
get_task_field() {
  local tasks_file="$1"
  local target_id="$2"
  local field="$3"

  local tasks_section
  tasks_section=$(sed -n '/^tasks:/,/^execution_plan:/p' "$tasks_file")

  local in_task=false
  while IFS= read -r line; do
    if echo "$line" | grep -q "^  - id: ${target_id}"; then
      in_task=true
      continue
    fi
    if [[ "$in_task" == "true" ]] && echo "$line" | grep -q '^  - id:'; then
      break
    fi
    [[ "$in_task" != "true" ]] && continue

    if echo "$line" | grep -q "    ${field}:"; then
      echo "$line" | sed "s/.*${field}: *//" | tr -d '"' | tr -d "'"
      return
    fi
  done <<< "$tasks_section"
}

# get_files_touched <tasks_yaml> <task_id>
# Outputs one file per line.
get_files_touched() {
  local tasks_file="$1"
  local target_id="$2"
  local in_task=false
  local in_files=false

  local tasks_section
  tasks_section=$(sed -n '/^tasks:/,/^execution_plan:/p' "$tasks_file")

  while IFS= read -r line; do
    if echo "$line" | grep -q "^  - id: ${target_id}"; then
      in_task=true
      continue
    fi
    if [[ "$in_task" == "true" ]] && echo "$line" | grep -q '^  - id:'; then
      break
    fi
    [[ "$in_task" != "true" ]] && continue

    if echo "$line" | grep -q '    files_touched:'; then
      in_files=true
      if echo "$line" | grep -q '\[\]'; then
        in_files=false
      fi
      continue
    fi

    if [[ "$in_files" == "true" ]]; then
      if echo "$line" | grep -qE '^\s+- '; then
        echo "$line" | sed 's/.*- //' | tr -d '"' | tr -d "'" | tr -d ' '
      else
        in_files=false
      fi
    fi
  done <<< "$tasks_section"
}

# get_prompt_context <tasks_yaml> <task_id>
# Outputs the prompt_context block for a task.
get_prompt_context() {
  local tasks_file="$1"
  local target_id="$2"

  local tasks_section
  tasks_section=$(sed -n '/^tasks:/,/^execution_plan:/p' "$tasks_file")

  local in_task=false
  local in_prompt=false
  local context=""

  while IFS= read -r line; do
    if echo "$line" | grep -q "^  - id: ${target_id}"; then
      in_task=true
      continue
    fi
    if [[ "$in_task" == "true" ]] && echo "$line" | grep -q '^  - id:'; then
      break
    fi
    [[ "$in_task" != "true" ]] && continue

    if echo "$line" | grep -q '    prompt_context:'; then
      in_prompt=true
      continue
    fi

    if [[ "$in_prompt" == "true" ]]; then
      # Prompt context lines are indented with 6+ spaces
      if echo "$line" | grep -qE '^\s{6}'; then
        context="${context}${line#      }
"
      else
        in_prompt=false
      fi
    fi
  done <<< "$tasks_section"

  echo "$context"
}

# get_execution_phases <tasks_yaml>
# Outputs "phase_num:parallel:task1,task2,..." per line.
get_execution_phases() {
  local tasks_file="$1"

  local exec_section
  exec_section=$(sed -n '/^execution_plan:/,/^validation:/p' "$tasks_file")

  local current_phase=""
  local is_parallel="false"
  local phase_tasks=""

  while IFS= read -r line; do
    if echo "$line" | grep -q '  - phase:'; then
      # Emit previous phase
      if [[ -n "$current_phase" ]]; then
        echo "${current_phase}:${is_parallel}:${phase_tasks}"
      fi
      current_phase=$(echo "$line" | sed 's/.*phase: *//' | tr -d '"')
      is_parallel="false"
      phase_tasks=""
      continue
    fi

    if echo "$line" | grep -q '    parallel:'; then
      local val
      val=$(echo "$line" | sed 's/.*parallel: *//' | tr -d '"' | tr -d ' ')
      is_parallel="$val"
      continue
    fi

    if echo "$line" | grep -qE '^\s+- [A-Z]+-[0-9]+'; then
      local tid
      tid=$(echo "$line" | sed 's/.*- //' | tr -d '"' | tr -d "'" | tr -d ' ')
      if [[ -n "$phase_tasks" ]]; then
        phase_tasks="${phase_tasks},${tid}"
      else
        phase_tasks="$tid"
      fi
    fi
  done <<< "$exec_section"

  # Emit last phase
  if [[ -n "$current_phase" ]]; then
    echo "${current_phase}:${is_parallel}:${phase_tasks}"
  fi
}

# compute_ready_tasks <tasks_yaml> <completed_tasks_space_separated>
# Outputs task IDs that are ready to run (all deps satisfied).
compute_ready_tasks() {
  local tasks_file="$1"
  local completed="$2"

  while IFS= read -r tid; do
    local deps
    deps=$(get_task_deps "$tasks_file" "$tid")

    # Skip if already completed
    if echo " $completed " | grep -q " ${tid} "; then
      continue
    fi

    # Check all deps satisfied
    local all_met=true
    for dep in $deps; do
      if ! echo " $completed " | grep -q " ${dep} "; then
        all_met=false
        break
      fi
    done

    if [[ "$all_met" == "true" ]]; then
      echo "$tid"
    fi
  done < <(get_all_task_ids "$tasks_file")
}

# check_parallel_safe <tasks_yaml> <task_id_1> <task_id_2>
# Returns 0 if tasks have no files_touched overlap, 1 otherwise.
check_parallel_safe() {
  local tasks_file="$1"
  local tid_a="$2"
  local tid_b="$3"

  local overlap
  overlap=$(comm -12 \
    <(get_files_touched "$tasks_file" "$tid_a" | sort) \
    <(get_files_touched "$tasks_file" "$tid_b" | sort) 2>/dev/null)

  if [[ -n "$overlap" ]]; then
    return 1
  fi
  return 0
}
