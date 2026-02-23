#!/usr/bin/env bash
# check_secrets.sh — Security dimension: scan for secrets, keys, credentials
# Output format: SEVERITY|CHECK|FILE|LINE|DESCRIPTION|REMEDIATION
set -euo pipefail

REPO_PATH="${1:?Usage: check_secrets.sh <repo_path>}"
FINDINGS=0

# Common source file includes for grep (brace expansion doesn't work in --include)
SOURCE_INCLUDES=(
  --include='*.sh' --include='*.py' --include='*.js' --include='*.ts'
  --include='*.go' --include='*.rb' --include='*.java' --include='*.rs'
  --include='*.yml' --include='*.yaml' --include='*.json' --include='*.toml'
  --include='*.xml' --include='*.cfg' --include='*.conf' --include='*.ini'
  --include='*.tf' --include='*.tfvars' --include='*.env' --include='*.env.*'
  --exclude-dir='.git' --exclude-dir='node_modules' --exclude-dir='.claude'
)

emit() {
  echo "$1|$2|$3|$4|$5|$6"
  FINDINGS=$((FINDINGS + 1))
}

# --- .env files ---
while IFS= read -r -d '' f; do
  emit "CRITICAL" "env_file" "$f" "-" ".env file found — may contain secrets" "Remove file and add .env to .gitignore"
done < <(find "$REPO_PATH" -name '.env' -o -name '.env.*' -not -name '.env.example' -not -name '.env.sample' -not -name '.env.template' 2>/dev/null | tr '\n' '\0')

# --- Private keys ---
while IFS= read -r -d '' f; do
  emit "CRITICAL" "private_key_file" "$f" "-" "Potential private key file detected" "Remove file and rotate the key immediately"
done < <(find "$REPO_PATH" -type f \( -name '*.pem' -o -name '*.key' -o -name '*.p12' -o -name '*.pfx' -o -name 'id_rsa' -o -name 'id_ed25519' -o -name 'id_ecdsa' -o -name 'id_dsa' \) 2>/dev/null | tr '\n' '\0')

# --- Private key content patterns ---
while IFS= read -r -d '' f; do
  # Skip binary files
  file "$f" | grep -q text || continue
  line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    if echo "$line" | grep -qE 'BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY'; then
      emit "CRITICAL" "private_key_content" "$f" "$line_num" "Private key content found in file" "Remove the key and rotate credentials"
    fi
  done < "$f"
done < <(find "$REPO_PATH" -type f -size -1M \( -name '*.md' -o -name '*.txt' -o -name '*.yml' -o -name '*.yaml' -o -name '*.json' -o -name '*.xml' -o -name '*.cfg' -o -name '*.conf' -o -name '*.sh' -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.rb' -o -name '*.go' -o -name '*.java' -o -name '*.rs' -o -name '*.toml' -o -name '*.ini' -o -name '*.env*' -o -name '*.pem' -o -name '*.key' \) 2>/dev/null | tr '\n' '\0')

# --- AWS credential patterns ---
while IFS= read -r result; do
  f=$(echo "$result" | cut -d: -f1)
  ln=$(echo "$result" | cut -d: -f2)
  emit "CRITICAL" "aws_credentials" "$f" "$ln" "Potential AWS access key found (AKIA pattern)" "Remove and rotate AWS credentials"
done < <(grep -rnE '(AKIA[0-9A-Z]{16}|aws_secret_access_key\s*=)' "$REPO_PATH" "${SOURCE_INCLUDES[@]}" 2>/dev/null || true)

# --- Generic secret patterns ---
while IFS= read -r result; do
  f=$(echo "$result" | cut -d: -f1)
  ln=$(echo "$result" | cut -d: -f2)
  emit "HIGH" "hardcoded_secret" "$f" "$ln" "Potential hardcoded secret or token" "Move secret to environment variable or vault"
done < <(grep -rnEi '(api[_-]?key|api[_-]?secret|auth[_-]?token|access[_-]?token|secret[_-]?key|private[_-]?key|password)\s*[:=]\s*["\x27][A-Za-z0-9+/=_-]{8,}' "$REPO_PATH" "${SOURCE_INCLUDES[@]}" 2>/dev/null || true)

# --- Hardcoded IPs / internal domains ---
while IFS= read -r result; do
  f=$(echo "$result" | cut -d: -f1)
  ln=$(echo "$result" | cut -d: -f2)
  # Skip common safe IPs (localhost, 0.0.0.0, metadata)
  matched=$(echo "$result" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
  case "$matched" in
    127.0.0.1|0.0.0.0|255.255.255.*|169.254.169.254) continue ;;
  esac
  emit "HIGH" "hardcoded_ip" "$f" "$ln" "Hardcoded IP address found: $matched" "Replace with configurable hostname or DNS"
done < <(grep -rnE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$REPO_PATH" "${SOURCE_INCLUDES[@]}" 2>/dev/null | grep -vE '(127\.0\.0\.1|0\.0\.0\.0|255\.255\.255|169\.254\.169\.254|version|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-|\.\*)' || true)

# --- PII: email addresses in source code ---
while IFS= read -r result; do
  f=$(echo "$result" | cut -d: -f1)
  ln=$(echo "$result" | cut -d: -f2)
  matched=$(echo "$result" | grep -oEi '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
  # Skip common non-personal emails
  case "$matched" in
    *@example.com|*@example.org|*@localhost|*@users.noreply.github.com|noreply@*) continue ;;
  esac
  emit "HIGH" "pii_email" "$f" "$ln" "Email address found: ${matched}" "Remove personal email or replace with a generic contact"
done < <(grep -rnEi '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$REPO_PATH" \
  "${SOURCE_INCLUDES[@]}" --include='*.md' --include='*.txt' --include='*.html' --include='*.xml' \
  --exclude-dir='.git' --exclude-dir='node_modules' \
  2>/dev/null | grep -vEi '(example\.com|example\.org|localhost|users\.noreply\.github\.com|noreply@|@spdx\.org|@changeset)' || true)

# --- PII: phone numbers in source code ---
while IFS= read -r result; do
  f=$(echo "$result" | cut -d: -f1)
  ln=$(echo "$result" | cut -d: -f2)
  emit "HIGH" "pii_phone" "$f" "$ln" "Potential phone number found in source code" "Remove personal phone numbers before going public"
done < <(grep -rnE '(\+?1[-.\s]?)?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}\b' "$REPO_PATH" \
  "${SOURCE_INCLUDES[@]}" --include='*.md' --include='*.txt' --include='*.html' \
  --exclude-dir='.git' --exclude-dir='node_modules' \
  2>/dev/null | grep -vE '(test|mock|fake|example|fixture|sample|placeholder|0000|1234|5551)' || true)

# --- GitHub Actions: hardcoded secrets in workflows ---
if [[ -d "$REPO_PATH/.github/workflows" ]]; then
  while IFS= read -r result; do
    f=$(echo "$result" | cut -d: -f1)
    ln=$(echo "$result" | cut -d: -f2)
    emit "CRITICAL" "actions_hardcoded_secret" "$f" "$ln" "Potential hardcoded secret in GitHub Actions workflow" "Use GitHub Actions secrets (secrets.YOUR_SECRET) instead of hardcoded values"
  done < <(grep -rnEi '(api[_-]?key|token|password|secret|credential)\s*[:=]\s*["\x27][A-Za-z0-9+/=_-]{8,}' "$REPO_PATH/.github/workflows/" --include='*.yml' --include='*.yaml' 2>/dev/null || true)

  # Unsafe use of github.event context (script injection risk)
  while IFS= read -r result; do
    f=$(echo "$result" | cut -d: -f1)
    ln=$(echo "$result" | cut -d: -f2)
    emit "HIGH" "actions_script_injection" "$f" "$ln" "Unsafe use of github.event context — potential script injection" "Use an intermediate environment variable instead of inline expression"
  done < <(grep -rnE '\$\{\{\s*github\.event\.(issue|pull_request|comment)\.(title|body|head\.ref)' "$REPO_PATH/.github/workflows/" --include='*.yml' --include='*.yaml' 2>/dev/null || true)
fi

# --- gitleaks (if available) ---
if command -v gitleaks &>/dev/null; then
  if command -v jq &>/dev/null; then
    while IFS= read -r leak_line; do
      f=$(echo "$leak_line" | jq -r '.File // "-"')
      ln=$(echo "$leak_line" | jq -r '.StartLine // "-"')
      desc=$(echo "$leak_line" | jq -r '.Description // "Secret detected by gitleaks"')
      emit "CRITICAL" "gitleaks" "$f" "$ln" "$desc" "Remove secret and rotate credentials"
    done < <(gitleaks detect --source "$REPO_PATH" --report-format json --no-banner 2>/dev/null | jq -c '.[]' 2>/dev/null || true)
  else
    echo "SKIPPED|gitleaks_jq|-|-|jq not installed — cannot parse gitleaks JSON output|Install: brew install jq"
  fi
else
  echo "SKIPPED|gitleaks|-|-|gitleaks not installed — git history not scanned|Install: brew install gitleaks"
fi

exit 0
