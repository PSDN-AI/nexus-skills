#!/usr/bin/env bash
# decompose.sh — Main entry point for PRD Decompose
# Usage: decompose.sh <prd_path> [options]
# Output: Structured domain folders with specs, boundaries, and contracts
set -euo pipefail

VERSION="0.1.0"

# Require bash 4+ (associative arrays)
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "Error: bash 4.0+ required (found ${BASH_VERSION})." >&2
  echo "  macOS: brew install bash" >&2
  echo "  Linux: sudo apt-get install bash" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Source library modules ---
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/parser.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/classifier.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/generator.sh"

# --- Defaults ---
OUTPUT_DIR="./prd-output"
TAXONOMY_FILE="${SKILL_DIR}/references/domain-taxonomy.yaml"
DRY_RUN=false
VERBOSE=false
PRD_PATH=""

# --- Parse arguments ---
show_usage() {
  cat <<EOF
Usage: decompose.sh <prd_path> [options]

Decompose a PRD into domain-specific specs for AI Agent consumption.

Arguments:
  prd_path              Path to PRD file (.md or .txt)

Options:
  -o, --output DIR      Output directory (default: ./prd-output)
  -t, --taxonomy FILE   Custom domain taxonomy YAML
  --dry-run             Parse & classify only, print summary
  -v, --verbose         Show detailed processing info
  --version             Print version and exit
  -h, --help            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      echo "prd-decompose ${VERSION}"
      exit 0
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    -o|--output)
      OUTPUT_DIR="${2:?--output requires a directory path}"
      shift 2
      ;;
    -t|--taxonomy)
      TAXONOMY_FILE="${2:?--taxonomy requires a file path}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      show_usage >&2
      exit 1
      ;;
    *)
      if [[ -z "$PRD_PATH" ]]; then
        PRD_PATH="$1"
      else
        echo "Error: Unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

# --- Validate inputs ---
if [[ -z "$PRD_PATH" ]]; then
  echo "Error: PRD file path is required." >&2
  show_usage >&2
  exit 1
fi

if [[ ! -f "$PRD_PATH" ]]; then
  echo "Error: PRD file not found: ${PRD_PATH}" >&2
  exit 1
fi

if [[ ! -r "$PRD_PATH" ]]; then
  echo "Error: PRD file not readable: ${PRD_PATH}" >&2
  exit 1
fi

PRD_PATH=$(cd "$(dirname "$PRD_PATH")" && pwd)/$(basename "$PRD_PATH")

if [[ ! -f "$TAXONOMY_FILE" ]]; then
  echo "Error: Taxonomy file not found: ${TAXONOMY_FILE}" >&2
  exit 3
fi

# --- Setup ---
# Support SOURCE_DATE_EPOCH for reproducible output (see reproducible-builds.org)
if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
  TIMESTAMP=$(date -u -d "@${SOURCE_DATE_EPOCH}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u -r "${SOURCE_DATE_EPOCH}" '+%Y-%m-%dT%H:%M:%SZ')
else
  TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
fi
PRD_TITLE=$(extract_prd_title "$PRD_PATH")
export TIMESTAMP PRD_TITLE
PRD_FILENAME=$(basename "$PRD_PATH")
TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

log() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo "[prd-decompose] $*" >&2
  fi
}

# ============================================================
# Phase 1: PARSE
# ============================================================
log "Phase 1: Parsing PRD..."

SECTIONS_FILE="${TMPDIR_WORK}/sections.txt"
parse_sections "$PRD_PATH" "$SECTIONS_FILE"

TOTAL_SECTIONS=$(wc -l < "$SECTIONS_FILE" | tr -d ' ')
log "  Found ${TOTAL_SECTIONS} sections"

if [[ "$TOTAL_SECTIONS" -eq 0 ]]; then
  echo "Error: No sections detected in PRD. Check file format." >&2
  exit 2
fi

# ============================================================
# Phase 2: CLASSIFY
# ============================================================
log "Phase 2: Classifying sections..."

load_taxonomy "$TAXONOMY_FILE"
log "  Loaded ${#DOMAIN_NAMES[@]} domains from taxonomy"

CLASSIFIED_FILE="${TMPDIR_WORK}/classified.txt"
classify_all_sections "$SECTIONS_FILE" "$PRD_PATH" "$CLASSIFIED_FILE"

# Count results
declare -A DOMAIN_COUNTS=()
UNCATEGORIZED_COUNT=0
while IFS='|' read -r _level _heading _start _end domain _score _words _cross; do
  if [[ "$domain" == "uncategorized" ]]; then
    UNCATEGORIZED_COUNT=$((UNCATEGORIZED_COUNT + 1))
  else
    DOMAIN_COUNTS["$domain"]=$(( ${DOMAIN_COUNTS[$domain]:-0} + 1 ))
  fi
done < "$CLASSIFIED_FILE"

CLASSIFIED_COUNT=$((TOTAL_SECTIONS - UNCATEGORIZED_COUNT))
if [[ $TOTAL_SECTIONS -gt 0 ]]; then
  COVERAGE=$(( CLASSIFIED_COUNT * 100 / TOTAL_SECTIONS ))
else
  COVERAGE=0
fi

log "  Classified ${CLASSIFIED_COUNT}/${TOTAL_SECTIONS} sections (${COVERAGE}% coverage)"

# ============================================================
# DRY RUN — print summary and exit
# ============================================================
if [[ "$DRY_RUN" == "true" ]]; then
  echo "PRD Decomposition Summary (Dry Run)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📄 Source:     ${PRD_FILENAME}"
  echo "📊 Sections:   ${TOTAL_SECTIONS} total → ${CLASSIFIED_COUNT} classified, ${UNCATEGORIZED_COUNT} uncategorized"
  echo ""
  echo "Domain Breakdown:"
  for domain in "${!DOMAIN_COUNTS[@]}"; do
    printf "  ├── %-15s %d sections\n" "${domain}/" "${DOMAIN_COUNTS[$domain]}"
  done
  echo ""
  echo "Coverage: ${COVERAGE}%"
  echo ""

  if [[ $UNCATEGORIZED_COUNT -gt 0 ]]; then
    echo "⚠️  Uncategorized sections:"
    while IFS='|' read -r _level heading _start _end domain _score _words _cross; do
      [[ "$domain" != "uncategorized" ]] && continue
      echo "  - ${heading}"
    done < "$CLASSIFIED_FILE"
  fi

  echo ""
  echo "Section Classification Detail:"
  while IFS='|' read -r level heading _start _end domain score _words cross_domain; do
    indent=""
    for ((i = 1; i < level; i++)); do indent="  ${indent}"; done
    cross_info=""
    [[ -n "$cross_domain" ]] && cross_info=" (cross-ref: ${cross_domain})"
    printf "  %s%-40s → %-15s score=%s%s\n" "$indent" "$heading" "$domain" "$score" "$cross_info"
  done < "$CLASSIFIED_FILE"

  exit 0
fi

# ============================================================
# Phase 3-5: EXTRACT, CONNECT, GENERATE
# ============================================================
log "Phase 3-5: Generating output..."

# Create output directory (with safety checks)
if [[ -d "$OUTPUT_DIR" ]]; then
  # Resolve to absolute for safety check
  _resolved_dir=$(cd "$OUTPUT_DIR" && pwd)
  # Block dangerous paths: filesystem root or user home
  if [[ "$_resolved_dir" == "/" || "$_resolved_dir" == "$HOME" ]]; then
    echo "Error: Refusing to overwrite dangerous path: ${_resolved_dir}" >&2
    exit 1
  fi
  # Only auto-clean directories that look like previous decomposer output
  if [[ -f "${OUTPUT_DIR}/meta.yaml" ]]; then
    log "  Output directory is previous decomposer output, cleaning: ${OUTPUT_DIR}"
    rm -rf "$OUTPUT_DIR"
  elif [[ -z "$(ls -A "$OUTPUT_DIR" 2>/dev/null)" ]]; then
    log "  Output directory is empty, reusing: ${OUTPUT_DIR}"
  else
    echo "Error: Output directory exists and is not a previous decomposer output: ${OUTPUT_DIR}" >&2
    echo "  Remove it manually or choose a different --output path." >&2
    exit 1
  fi
fi
mkdir -p "$OUTPUT_DIR"

# Resolve to absolute path
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)

# Generate domain folders
UNIQUE_DOMAINS=()
while IFS='|' read -r _level _heading _start _end domain _score _words _cross; do
  [[ "$domain" == "uncategorized" ]] && continue
  found=false
  for d in "${UNIQUE_DOMAINS[@]:-}"; do
    [[ "$d" == "$domain" ]] && found=true && break
  done
  [[ "$found" == "false" ]] && UNIQUE_DOMAINS+=("$domain")
done < "$CLASSIFIED_FILE"

for domain in "${UNIQUE_DOMAINS[@]}"; do
  log "  Generating ${domain}/..."
  generate_domain_spec "$domain" "$CLASSIFIED_FILE" "$PRD_PATH" "$OUTPUT_DIR"
  generate_boundary "$domain" "$CLASSIFIED_FILE" "$PRD_PATH" "$OUTPUT_DIR"
  generate_config "$domain" "$OUTPUT_DIR"
done

# Generate uncategorized if needed
generate_uncategorized "$CLASSIFIED_FILE" "$PRD_PATH" "$OUTPUT_DIR"

# Generate contracts
log "  Generating contracts/..."
CONTRACT_COUNT=$(generate_contracts "$CLASSIFIED_FILE" "$PRD_PATH" "$OUTPUT_DIR")

# Generate meta.yaml
log "  Generating meta.yaml..."
generate_meta "$CLASSIFIED_FILE" "$PRD_PATH" "$OUTPUT_DIR" "$CONTRACT_COUNT"

# ============================================================
# Phase 6: VALIDATE
# ============================================================
log "Phase 6: Validating output..."

WARNINGS=()

# Check all sections are accounted for
GENERATED_SECTIONS=0
for domain in "${UNIQUE_DOMAINS[@]}"; do
  [[ -f "${OUTPUT_DIR}/${domain}/spec.md" ]] && GENERATED_SECTIONS=$((GENERATED_SECTIONS + 1))
done
[[ -d "${OUTPUT_DIR}/uncategorized" ]] && GENERATED_SECTIONS=$((GENERATED_SECTIONS + 1))

# Check for uncategorized sections
if [[ $UNCATEGORIZED_COUNT -gt 0 ]]; then
  while IFS='|' read -r _level heading _start _end domain _score _words _cross; do
    [[ "$domain" != "uncategorized" ]] && continue
    WARNINGS+=("Section \"${heading}\" has no domain classification")
  done < "$CLASSIFIED_FILE"
fi

# Count acceptance criteria per domain
declare -A AC_COUNTS=()
for domain in "${UNIQUE_DOMAINS[@]}"; do
  bf="${OUTPUT_DIR}/${domain}/boundary.yaml"
  if [[ -f "$bf" ]]; then
    ac_count=$(grep -c '  - id:' "$bf" 2>/dev/null || echo "0")
    ac_count=$(echo "$ac_count" | tr -d '[:space:]')
    AC_COUNTS["$domain"]="$ac_count"
  fi
done

# ============================================================
# Output Report
# ============================================================
echo "✅ PRD Decomposition Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📄 Source:     ${PRD_FILENAME}"
echo "📁 Output:     ${OUTPUT_DIR}"
echo "📊 Sections:   ${TOTAL_SECTIONS} total → ${CLASSIFIED_COUNT} classified, ${UNCATEGORIZED_COUNT} uncategorized"
echo ""
echo "Domain Breakdown:"
for domain in "${UNIQUE_DOMAINS[@]}"; do
  req_count="${DOMAIN_COUNTS[$domain]:-0}"
  ac_count="${AC_COUNTS[$domain]:-0}"
  printf "  ├── %-15s %d requirements, %d acceptance criteria\n" "${domain}/" "$req_count" "$ac_count"
done
echo ""
echo "Contracts: ${CONTRACT_COUNT} API contracts identified"
echo "Coverage: ${COVERAGE}% (${UNCATEGORIZED_COUNT} sections uncategorized)"

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo ""
  echo "⚠️  Warnings:"
  for w in "${WARNINGS[@]}"; do
    echo "  - ${w}"
  done
fi
