#!/usr/bin/env bash
# check_secrets.sh — Security dimension: scan for secrets, keys, credentials
# Output format: SEVERITY|CHECK|FILE|LINE|DESCRIPTION|REMEDIATION
set -euo pipefail

REPO_PATH="${1:?Usage: check_secrets.sh <repo_path>}"
FINDINGS=0

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
done < <(grep -rnE '(AKIA[0-9A-Z]{16}|aws_secret_access_key\s*=)' "$REPO_PATH" --include='*.{sh,py,js,ts,go,rb,java,yml,yaml,json,toml,cfg,conf,ini,env,env.*,tf,tfvars}' 2>/dev/null || true)

# --- Generic secret patterns ---
while IFS= read -r result; do
  f=$(echo "$result" | cut -d: -f1)
  ln=$(echo "$result" | cut -d: -f2)
  emit "HIGH" "hardcoded_secret" "$f" "$ln" "Potential hardcoded secret or token" "Move secret to environment variable or vault"
done < <(grep -rnEi '(api[_-]?key|api[_-]?secret|auth[_-]?token|access[_-]?token|secret[_-]?key|private[_-]?key|password)\s*[:=]\s*["\x27][A-Za-z0-9+/=_-]{8,}' "$REPO_PATH" --include='*.{sh,py,js,ts,go,rb,java,yml,yaml,json,toml,cfg,conf,ini,tf,tfvars}' 2>/dev/null || true)

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
done < <(grep -rnE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$REPO_PATH" --include='*.{sh,py,js,ts,go,rb,java,yml,yaml,json,toml,cfg,conf,ini,tf,tfvars}' 2>/dev/null | grep -vE '(127\.0\.0\.1|0\.0\.0\.0|255\.255\.255|169\.254\.169\.254|version|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-|\.\*)' || true)

# --- gitleaks (if available) ---
if command -v gitleaks &>/dev/null; then
  while IFS= read -r leak_line; do
    f=$(echo "$leak_line" | jq -r '.File // "-"' 2>/dev/null || echo "-")
    ln=$(echo "$leak_line" | jq -r '.StartLine // "-"' 2>/dev/null || echo "-")
    desc=$(echo "$leak_line" | jq -r '.Description // "Secret detected by gitleaks"' 2>/dev/null || echo "Secret detected by gitleaks")
    emit "CRITICAL" "gitleaks" "$f" "$ln" "$desc" "Remove secret and rotate credentials"
  done < <(gitleaks detect --source "$REPO_PATH" --report-format json --no-banner 2>/dev/null | jq -c '.[]' 2>/dev/null || true)
else
  echo "SKIPPED|gitleaks|-|-|gitleaks not installed — git history not scanned|Install: brew install gitleaks"
fi

exit 0
