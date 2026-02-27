#!/usr/bin/env bash
# classifier.sh — Domain classification logic
# Scores PRD sections against domain taxonomy keywords.
# Sourced by decompose.sh; expects TAXONOMY_FILE to be set.
set -euo pipefail

# Global arrays populated by load_taxonomy
declare -a DOMAIN_NAMES=()
declare -A DOMAIN_KEYWORDS=()

# load_taxonomy <taxonomy_file>
# Parses the YAML taxonomy into DOMAIN_NAMES and DOMAIN_KEYWORDS arrays.
# Uses basic text parsing — does not require yq.
load_taxonomy() {
  local taxonomy_file="$1"
  local current_domain=""
  local in_keywords=false
  local keywords_str=""

  DOMAIN_NAMES=()
  DOMAIN_KEYWORDS=()

  while IFS= read -r line; do
    # Detect domain name
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.*) ]]; then
      # Save previous domain's keywords
      if [[ -n "$current_domain" && -n "$keywords_str" ]]; then
        DOMAIN_KEYWORDS["$current_domain"]="$keywords_str"
      fi
      current_domain="${BASH_REMATCH[1]}"
      current_domain=$(echo "$current_domain" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      DOMAIN_NAMES+=("$current_domain")
      keywords_str=""
      in_keywords=false
    fi

    # Detect keywords section
    if [[ "$line" =~ ^[[:space:]]*keywords:[[:space:]]*$ ]]; then
      in_keywords=true
      continue
    fi

    # Detect end of keywords (next non-keyword line)
    if [[ "$in_keywords" == "true" ]]; then
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.*) ]]; then
        local kw="${BASH_REMATCH[1]}"
        # Strip quotes if present
        kw=$(echo "$kw" | sed "s/^[\"']//;s/[\"']$//")
        if [[ -n "$keywords_str" ]]; then
          keywords_str="${keywords_str}|${kw}"
        else
          keywords_str="$kw"
        fi
      else
        # Non-list line while in keywords — end of keywords block
        if [[ ! "$line" =~ ^[[:space:]]*$ ]]; then
          in_keywords=false
        fi
      fi
    fi
  done < "$taxonomy_file"

  # Save last domain's keywords
  if [[ -n "$current_domain" && -n "$keywords_str" ]]; then
    DOMAIN_KEYWORDS["$current_domain"]="$keywords_str"
  fi
}

# classify_section <section_content>
# Prints: DOMAIN|SCORE|TOTAL_WORDS
# Returns the best-matching domain for the given content.
classify_section() {
  local content="$1"
  local best_domain="uncategorized"
  local best_score=0
  local second_score=0
  local second_domain=""
  local total_words

  # Count total words for normalization
  total_words=$(echo "$content" | wc -w | tr -d ' ')
  [[ "$total_words" -eq 0 ]] && total_words=1

  local domain
  for domain in "${DOMAIN_NAMES[@]}"; do
    local keywords_pipe="${DOMAIN_KEYWORDS[$domain]:-}"
    [[ -z "$keywords_pipe" ]] && continue

    local score=0
    local kw
    # Split keywords by pipe
    while IFS='|' read -ra kw_array; do
      for kw in "${kw_array[@]}"; do
        [[ -z "$kw" ]] && continue
        # Case-insensitive word matching
        local matches
        matches=$(echo "$content" | grep -ioE "(^|[^a-zA-Z])${kw}([^a-zA-Z]|$)" 2>/dev/null | wc -l | tr -d ' ')
        score=$((score + matches))
      done
    done <<< "$keywords_pipe"

    if [[ $score -gt $best_score ]]; then
      second_score=$best_score
      second_domain=$best_domain
      best_score=$score
      best_domain=$domain
    elif [[ $score -gt $second_score ]]; then
      second_score=$score
      second_domain=$domain
    fi
  done

  # Check for cross-domain reference (second domain scores >60% of top)
  local cross_domain=""
  if [[ $best_score -gt 0 && $second_score -gt 0 ]]; then
    local threshold=$(( best_score * 60 / 100 ))
    if [[ $second_score -ge $threshold && -n "$second_domain" ]]; then
      cross_domain="$second_domain"
    fi
  fi

  if [[ $best_score -eq 0 ]]; then
    best_domain="uncategorized"
  fi

  echo "${best_domain}|${best_score}|${total_words}|${cross_domain}"
}

# classify_all_sections <sections_file> <prd_file> <output_file>
# Reads sections file, classifies each, writes:
# LEVEL|HEADING|START|END|DOMAIN|SCORE|WORDS|CROSS_DOMAIN
classify_all_sections() {
  local sections_file="$1"
  local prd_file="$2"
  local output_file="$3"

  : > "$output_file"

  while IFS='|' read -r level heading start end; do
    local content
    content=$(sed -n "${start},${end}p" "$prd_file")

    local result
    result=$(classify_section "$content")

    echo "${level}|${heading}|${start}|${end}|${result}" >> "$output_file"
  done < "$sections_file"
}
