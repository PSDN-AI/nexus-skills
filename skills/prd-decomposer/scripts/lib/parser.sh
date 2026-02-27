#!/usr/bin/env bash
# parser.sh — PRD section parsing logic
# Parses a Markdown or plain text PRD into sections.
# Outputs one line per section: LEVEL|HEADING|START_LINE|END_LINE
# Sourced by decompose.sh; expects PRD_PATH to be set.
set -euo pipefail

# parse_sections <prd_file> <output_file>
# Writes sections to output_file in format: LEVEL|HEADING|START_LINE|END_LINE
parse_sections() {
  local prd_file="$1"
  local output_file="$2"
  local total_lines
  total_lines=$(wc -l < "$prd_file" | tr -d ' ')

  # Collect heading positions
  local -a heading_lines=()
  local -a heading_levels=()
  local -a heading_texts=()
  local line_num=0
  local in_code_block=false
  local found_markdown_heading=false

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))

    # Track code blocks to skip headings inside them
    if [[ "$line" =~ ^\`\`\` ]]; then
      if [[ "$in_code_block" == "true" ]]; then
        in_code_block=false
      else
        in_code_block=true
      fi
      continue
    fi

    [[ "$in_code_block" == "true" ]] && continue

    # Detect Markdown headings: # through ####
    if [[ "$line" =~ ^(#{1,4})[[:space:]]+(.*) ]]; then
      local hashes="${BASH_REMATCH[1]}"
      local text="${BASH_REMATCH[2]}"
      local level=${#hashes}
      heading_lines+=("$line_num")
      heading_levels+=("$level")
      heading_texts+=("$text")
      found_markdown_heading=true
    # Detect numbered sections for plain text: 1. Title, 1.2 Title
    elif [[ "$line" =~ ^[0-9]+(\.[0-9]+)*\.?[[:space:]]+(.*) && "$found_markdown_heading" == "false" ]]; then
      # Only use numbered detection if no Markdown headings found
      local text="${BASH_REMATCH[2]}"
      local dots
      dots=$(echo "$line" | grep -o '\.' | wc -l | tr -d ' ' || true)
      local level=$((dots + 1))
      [[ $level -gt 4 ]] && level=4
      heading_lines+=("$line_num")
      heading_levels+=("$level")
      heading_texts+=("$text")
    fi
  done < "$prd_file"

  # Write sections: each section runs from its heading to the line before the next heading
  local count=${#heading_lines[@]}
  : > "$output_file"

  if [[ $count -eq 0 ]]; then
    # No headings found — treat entire file as one section
    echo "1|Untitled|1|${total_lines}" >> "$output_file"
    return
  fi

  local i
  for ((i = 0; i < count; i++)); do
    local start="${heading_lines[$i]}"
    local level="${heading_levels[$i]}"
    local text="${heading_texts[$i]}"
    local end

    if [[ $((i + 1)) -lt $count ]]; then
      end=$(( heading_lines[$((i + 1))] - 1 ))
    else
      end="$total_lines"
    fi

    # Clean heading text: remove trailing whitespace and special chars
    text=$(echo "$text" | sed 's/[[:space:]]*$//')

    echo "${level}|${text}|${start}|${end}" >> "$output_file"
  done
}

# extract_section_content <prd_file> <start_line> <end_line>
# Prints the content of lines start_line through end_line (inclusive)
extract_section_content() {
  local prd_file="$1"
  local start="$2"
  local end="$3"
  sed -n "${start},${end}p" "$prd_file"
}

# extract_prd_title <prd_file>
# Returns the first H1 heading text, or filename if no H1 found
extract_prd_title() {
  local prd_file="$1"
  local title
  title=$(grep -m1 '^#[[:space:]]' "$prd_file" 2>/dev/null | sed 's/^#[[:space:]]*//' || true)
  if [[ -z "$title" ]]; then
    title=$(basename "$prd_file" | sed 's/\.[^.]*$//')
  fi
  echo "$title"
}

# extract_prd_metadata <prd_file>
# Prints metadata lines: KEY|VALUE
extract_prd_metadata() {
  local prd_file="$1"
  # Look for **Key**: Value or Key: Value patterns in the first 20 lines
  head -20 "$prd_file" | while IFS= read -r line; do
    # Match **Author**: Value
    if [[ "$line" =~ ^\*\*([Aa]uthor)\*\*:[[:space:]]*(.*) ]]; then
      echo "author|${BASH_REMATCH[2]}"
    elif [[ "$line" =~ ^\*\*([Dd]ate)\*\*:[[:space:]]*(.*) ]]; then
      echo "date|${BASH_REMATCH[2]}"
    elif [[ "$line" =~ ^\*\*([Vv]ersion)\*\*:[[:space:]]*(.*) ]]; then
      echo "version|${BASH_REMATCH[2]}"
    fi
  done
}
