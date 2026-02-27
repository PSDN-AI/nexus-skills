#!/usr/bin/env bash
# generator.sh — Output generation logic
# Generates domain folders, specs, boundary conditions, contracts, and metadata.
# Sourced by decompose.sh; expects OUTPUT_DIR, PRD_PATH, PRD_TITLE, TIMESTAMP to be set.
set -euo pipefail

# generate_domain_spec <domain> <classified_sections_file> <prd_file> <output_dir>
# Creates {output_dir}/{domain}/spec.md from classified sections
generate_domain_spec() {
  local domain="$1"
  local classified_file="$2"
  local prd_file="$3"
  local output_dir="$4"

  local domain_dir="${output_dir}/${domain}"
  mkdir -p "$domain_dir"

  local domain_title
  # Capitalize first letter (portable across macOS/Linux)
  local first_char
  first_char=$(echo "$domain" | cut -c1 | tr '[:lower:]' '[:upper:]')
  local rest
  rest=$(echo "$domain" | cut -c2- | sed 's/-/ /g')
  domain_title="${first_char}${rest}"

  # Collect source section headings
  local source_sections=""
  local requirements=""

  while IFS='|' read -r _level heading start end sec_domain _score _words _cross; do
    [[ "$sec_domain" != "$domain" ]] && continue

    if [[ -n "$source_sections" ]]; then
      source_sections="${source_sections}, ${heading}"
    else
      source_sections="$heading"
    fi

    local content
    content=$(sed -n "${start},${end}p" "$prd_file")

    # Append extracted content
    if [[ -n "$requirements" ]]; then
      requirements="${requirements}

### ${heading}

[EXTRACTED]
${content}"
    else
      requirements="### ${heading}

[EXTRACTED]
${content}"
    fi
  done < "$classified_file"

  # Collect cross-domain dependencies
  local dependencies=""
  while IFS='|' read -r _level heading _start _end sec_domain _score _words cross_domain; do
    [[ "$sec_domain" != "$domain" ]] && continue
    [[ -z "$cross_domain" ]] && continue

    if [[ -n "$dependencies" ]]; then
      dependencies="${dependencies}
- Section \"${heading}\" has cross-domain reference to **${cross_domain}**"
    else
      dependencies="- Section \"${heading}\" has cross-domain reference to **${cross_domain}**"
    fi
  done < "$classified_file"

  [[ -z "$dependencies" ]] && dependencies="No cross-domain dependencies identified."

  cat > "${domain_dir}/spec.md" <<EOF
# ${domain_title} Specification

> Extracted from: ${PRD_TITLE}
> Generated: ${TIMESTAMP}
> Source sections: ${source_sections}

## Overview

[GENERATED] This specification covers the ${domain} domain requirements extracted from the PRD.

## Requirements

${requirements}

## Dependencies

[GENERATED] ${dependencies}

## Open Questions

[GENERATED] No open questions identified during automated decomposition. Review spec for completeness.
EOF
}

# generate_boundary <domain> <classified_sections_file> <prd_file> <output_dir>
# Creates {output_dir}/{domain}/boundary.yaml
generate_boundary() {
  local domain="$1"
  local classified_file="$2"
  local prd_file="$3"
  local output_dir="$4"
  local prd_filename
  prd_filename=$(basename "$prd_file")

  local domain_dir="${output_dir}/${domain}"
  mkdir -p "$domain_dir"

  # Start building the YAML
  local ac_entries=""
  local constraint_entries=""
  local test_entries=""
  local ac_id=0

  while IFS='|' read -r _level heading start end sec_domain _score _words _cross; do
    [[ "$sec_domain" != "$domain" ]] && continue

    local content
    content=$(sed -n "${start},${end}p" "$prd_file")

    # Extract "must"/"shall" statements as P0 acceptance criteria
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      ac_id=$((ac_id + 1))
      local ac_num
      ac_num=$(printf "AC-%03d" "$ac_id")
      # Clean the line for YAML safety
      local clean_line
      clean_line=$(echo "$line" | sed 's/^[[:space:]]*[-*][[:space:]]*//' | sed "s/\"/'/g" | head -c 200)
      ac_entries="${ac_entries}
  - id: \"${ac_num}\"
    description: \"${clean_line}\"
    source_section: \"${heading}\"
    priority: P0"
    done < <(echo "$content" | grep -iE '\b(must|shall|required|mandatory)\b' 2>/dev/null || true)

    # Extract "should" statements as P1
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      ac_id=$((ac_id + 1))
      local ac_num
      ac_num=$(printf "AC-%03d" "$ac_id")
      local clean_line
      clean_line=$(echo "$line" | sed 's/^[[:space:]]*[-*][[:space:]]*//' | sed "s/\"/'/g" | head -c 200)
      ac_entries="${ac_entries}
  - id: \"${ac_num}\"
    description: \"${clean_line}\"
    source_section: \"${heading}\"
    priority: P1"
    done < <(echo "$content" | grep -iE '\bshould\b' 2>/dev/null | grep -viE '\b(must|shall)\b' 2>/dev/null || true)

    # Extract constraint-like statements
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local clean_line
      clean_line=$(echo "$line" | sed 's/^[[:space:]]*[-*][[:space:]]*//' | sed "s/\"/'/g" | head -c 200)
      local constraint_type="compatibility"
      echo "$line" | grep -qiE 'perform|speed|latency|throughput|concurrent' && constraint_type="performance"
      echo "$line" | grep -qiE 'secur|encrypt|auth|compliance|PCI|GDPR' && constraint_type="security"
      echo "$line" | grep -qiE 'scal|replica|cluster|distributed|high.avail' && constraint_type="scalability"
      constraint_entries="${constraint_entries}
  - type: \"${constraint_type}\"
    description: \"${clean_line}\""
    done < <(echo "$content" | grep -iE '\b(constraint|limit|non.functional|requirement|compliance)\b' 2>/dev/null || true)

    # Generate test hints from requirements
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local clean_line
      clean_line=$(echo "$line" | sed 's/^[[:space:]]*[-*][[:space:]]*//' | sed "s/\"/'/g" | head -c 200)
      test_entries="${test_entries}
  - scenario: \"Verify: ${clean_line}\"
    expected: \"Requirement met as specified\""
    done < <(echo "$content" | grep -E '^[[:space:]]*[-*][[:space:]]' 2>/dev/null | head -10 || true)

  done < "$classified_file"

  # Default entries if empty
  [[ -z "$ac_entries" ]] && ac_entries="
  []"
  [[ -z "$constraint_entries" ]] && constraint_entries="
  []"
  [[ -z "$test_entries" ]] && test_entries="
  []"

  cat > "${domain_dir}/boundary.yaml" <<EOF
domain: "${domain}"
generated_from: "${prd_filename}"
generated_at: "${TIMESTAMP}"

acceptance_criteria:${ac_entries}

constraints:${constraint_entries}

test_hints:${test_entries}
EOF
}

# generate_config <domain> <output_dir>
# Creates {output_dir}/{domain}/config.yaml
generate_config() {
  local domain="$1"
  local output_dir="$2"

  local domain_dir="${output_dir}/${domain}"
  mkdir -p "$domain_dir"

  cat > "${domain_dir}/config.yaml" <<EOF
domain: "${domain}"
target_repo: ""
target_branch: ""
pr_template: "default"
agent_model: ""
max_iterations: 3
review_required: true
EOF
}

# generate_contracts <classified_sections_file> <prd_file> <output_dir>
# Creates contracts/ directory with API contracts, data contracts, and dependency graph
generate_contracts() {
  local classified_file="$1"
  local prd_file="$2"
  local output_dir="$3"

  local contracts_dir="${output_dir}/contracts"
  mkdir -p "$contracts_dir"

  # Collect domains and cross-reference pairs
  local -a all_domains=()
  local -a cross_from=()
  local -a cross_to=()

  while IFS='|' read -r _level _heading _start _end domain _score _words cross_domain; do
    [[ "$domain" == "uncategorized" ]] && continue

    # Track unique domains
    local found=false
    for d in "${all_domains[@]:-}"; do
      [[ "$d" == "$domain" ]] && found=true && break
    done
    [[ "$found" == "false" ]] && all_domains+=("$domain")

    # Track cross-references as parallel arrays
    if [[ -n "$cross_domain" ]]; then
      cross_from+=("$domain")
      cross_to+=("$cross_domain")
    fi
  done < "$classified_file"

  # Generate api-contracts.yaml
  local api_entries=""
  local api_count=0
  # Look for API endpoint patterns in the PRD
  while IFS= read -r line; do
    if [[ "$line" =~ (GET|POST|PUT|DELETE|PATCH)[[:space:]]+(/?[a-zA-Z0-9/_{}:-]+) ]]; then
      local method="${BASH_REMATCH[1]}"
      local path="${BASH_REMATCH[2]}"
      local desc
      desc=$(echo "$line" | sed 's/^[[:space:]]*[-*][[:space:]]*//' | sed "s/\"/'/g" | head -c 200)
      api_count=$((api_count + 1))
      api_entries="${api_entries}
  - name: \"API endpoint ${api_count}\"
    provider: backend
    consumers: [frontend]
    endpoints:
      - method: ${method}
        path: \"${path}\"
        description: \"${desc}\"
    status: draft"
    fi
  done < "$prd_file"

  if [[ -z "$api_entries" ]]; then
    api_entries="
  []"
  fi

  cat > "${contracts_dir}/api-contracts.yaml" <<EOF
contracts:${api_entries}
EOF

  # Generate data-contracts.yaml
  local data_entries=""
  while IFS= read -r line; do
    if [[ "$line" =~ (PostgreSQL|MySQL|MongoDB|Redis|DynamoDB|RDS|database|schema) ]]; then
      local desc
      desc=$(echo "$line" | sed 's/^[[:space:]]*[-*][[:space:]]*//' | sed "s/\"/'/g" | head -c 200)
      data_entries="${data_entries}
  - name: \"${desc}\"
    provider: backend
    consumers: [infra]
    status: draft"
    fi
  done < <(grep -iE '(PostgreSQL|MySQL|MongoDB|Redis|DynamoDB|RDS|database|schema)' "$prd_file" 2>/dev/null | head -10 || true)

  if [[ -z "$data_entries" ]]; then
    data_entries="
  []"
  fi

  cat > "${contracts_dir}/data-contracts.yaml" <<EOF
contracts:${data_entries}
EOF

  # Generate infra-requirements.yaml
  local infra_entries=""
  while IFS= read -r line; do
    if [[ "$line" =~ (EKS|GKE|AKS|Kubernetes|Docker|Terraform|CloudFront|CDN|S3|RDS|ElastiCache) ]]; then
      local desc
      desc=$(echo "$line" | sed 's/^[[:space:]]*[-*][[:space:]]*//' | sed "s/\"/'/g" | head -c 200)
      infra_entries="${infra_entries}
  - name: \"${desc}\"
    requester: backend
    resources:
      - type: compute
        description: \"${desc}\"
    status: draft"
    fi
  done < <(grep -iE '(EKS|GKE|AKS|Kubernetes|Docker|Terraform|CloudFront|CDN|S3|RDS|ElastiCache)' "$prd_file" 2>/dev/null | head -10 || true)

  if [[ -z "$infra_entries" ]]; then
    infra_entries="
  []"
  fi

  cat > "${contracts_dir}/infra-requirements.yaml" <<EOF
requirements:${infra_entries}
EOF

  # Generate dependency-graph.md
  local graph_edges=""
  local dep_rows=""
  local idx
  local cross_count=${#cross_from[@]}
  for ((idx = 0; idx < cross_count; idx++)); do
    local from_domain="${cross_from[$idx]}"
    local to_domain="${cross_to[$idx]}"
    local from_upper
    from_upper=$(echo "$from_domain" | cut -c1 | tr '[:lower:]' '[:upper:]')$(echo "$from_domain" | cut -c2-)
    local to_upper
    to_upper=$(echo "$to_domain" | cut -c1 | tr '[:lower:]' '[:upper:]')$(echo "$to_domain" | cut -c2-)
    graph_edges="${graph_edges}
    ${from_upper}[${from_domain}] --> ${to_upper}[${to_domain}]"
    dep_rows="${dep_rows}
| ${from_domain} | ${to_domain} | cross-reference | runtime |"
  done

  # Add standard domain relationships if they exist
  local has_fe=false has_be=false has_infra=false has_devops=false has_sec=false has_data=false
  for d in "${all_domains[@]:-}"; do
    case "$d" in
      frontend) has_fe=true ;;
      backend) has_be=true ;;
      infra) has_infra=true ;;
      devops) has_devops=true ;;
      security) has_sec=true ;;
      data) has_data=true ;;
    esac
  done

  if [[ -z "$graph_edges" ]]; then
    # Build from detected domains
    [[ "$has_fe" == "true" && "$has_be" == "true" ]] && graph_edges="${graph_edges}
    FE[Frontend] -->|API calls| BE[Backend]"
    [[ "$has_be" == "true" && "$has_data" == "true" ]] && graph_edges="${graph_edges}
    BE[Backend] -->|queries| DATA[Data]"
    [[ "$has_be" == "true" && "$has_infra" == "true" ]] && graph_edges="${graph_edges}
    BE[Backend] -->|deploys on| INFRA[Infrastructure]"
    [[ "$has_devops" == "true" && "$has_fe" == "true" ]] && graph_edges="${graph_edges}
    DEVOPS[DevOps] -->|builds| FE[Frontend]"
    [[ "$has_devops" == "true" && "$has_be" == "true" ]] && graph_edges="${graph_edges}
    DEVOPS[DevOps] -->|builds| BE[Backend]"
    [[ "$has_sec" == "true" && "$has_be" == "true" ]] && graph_edges="${graph_edges}
    SEC[Security] -.->|audits| BE[Backend]"
    [[ "$has_sec" == "true" && "$has_infra" == "true" ]] && graph_edges="${graph_edges}
    SEC[Security] -.->|audits| INFRA[Infrastructure]"
  fi

  cat > "${contracts_dir}/dependency-graph.md" <<EOF
# Dependency Graph

\`\`\`mermaid
graph LR${graph_edges}
\`\`\`

## Dependencies Detail

| From | To | Contract | Type |
|------|-----|----------|------|${dep_rows}
EOF

  echo "$api_count"
}

# generate_meta <classified_sections_file> <prd_file> <output_dir> <contract_count>
# Creates {output_dir}/meta.yaml
generate_meta() {
  local classified_file="$1"
  local prd_file="$2"
  local output_dir="$3"
  local contract_count="${4:-0}"
  local prd_filename
  prd_filename=$(basename "$prd_file")

  local total_sections=0
  local uncategorized=0
  local -a domains_list=()
  local ambiguity_count=0

  while IFS='|' read -r _level _heading _start _end domain _score _words cross_domain; do
    total_sections=$((total_sections + 1))

    if [[ "$domain" == "uncategorized" ]]; then
      uncategorized=$((uncategorized + 1))
    else
      # Track unique domains
      local found=false
      for d in "${domains_list[@]:-}"; do
        [[ "$d" == "$domain" ]] && found=true && break
      done
      [[ "$found" == "false" ]] && domains_list+=("$domain")
    fi

    [[ -n "$cross_domain" ]] && ambiguity_count=$((ambiguity_count + 1))
  done < "$classified_file"

  local classified=$((total_sections - uncategorized))
  local coverage=0
  if [[ $total_sections -gt 0 ]]; then
    coverage=$(( classified * 100 / total_sections ))
  fi

  local domains_str=""
  for d in "${domains_list[@]:-}"; do
    if [[ -n "$domains_str" ]]; then
      domains_str="${domains_str}, ${d}"
    else
      domains_str="$d"
    fi
  done

  cat > "${output_dir}/meta.yaml" <<EOF
project:
  name: "${PRD_TITLE}"
  prd_source: "${prd_filename}"
  generated_at: "${TIMESTAMP}"
  generator: "prd-decomposer@0.1.0"

decomposition:
  total_sections: ${total_sections}
  domains_identified: [${domains_str}]
  uncategorized_sections: ${uncategorized}
  cross_domain_contracts: ${contract_count}

completeness:
  coverage_percent: ${coverage}
  ambiguity_flags: ${ambiguity_count}
  missing_info_flags: 0
EOF
}

# generate_uncategorized <classified_sections_file> <prd_file> <output_dir>
# Creates uncategorized/spec.md if there are uncategorized sections
generate_uncategorized() {
  local classified_file="$1"
  local prd_file="$2"
  local output_dir="$3"

  local has_uncategorized=false
  local content=""

  while IFS='|' read -r _level heading start end domain _score _words _cross; do
    [[ "$domain" != "uncategorized" ]] && continue
    has_uncategorized=true

    local section_content
    section_content=$(sed -n "${start},${end}p" "$prd_file")
    content="${content}

### ${heading}

[EXTRACTED]
${section_content}"
  done < "$classified_file"

  if [[ "$has_uncategorized" == "true" ]]; then
    mkdir -p "${output_dir}/uncategorized"
    cat > "${output_dir}/uncategorized/spec.md" <<EOF
# Uncategorized Sections

> Extracted from: ${PRD_TITLE}
> Generated: ${TIMESTAMP}
> These sections could not be classified into a specific domain.

## Sections
${content}
EOF
  fi
}
