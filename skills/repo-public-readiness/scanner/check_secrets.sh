#!/usr/bin/env bash
# check_secrets.sh — Security dimension: scan for secrets, keys, credentials
# Output format: SEVERITY|CHECK|FILE|LINE|DESCRIPTION|REMEDIATION
set -euo pipefail

# Require bash 4+ (associative arrays used for BIP-39 lookup)
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "Error: bash 4.0+ required (found ${BASH_VERSION})." >&2
  echo "  macOS: brew install bash" >&2
  echo "  Linux: sudo apt-get install bash" >&2
  exit 1
fi

REPO_PATH="${1:?Usage: check_secrets.sh <repo_path>}"
FINDINGS=0

# Common source file includes for grep (brace expansion doesn't work in --include)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
# shellcheck disable=SC2094  # False positive: emit writes to stdout, not to $f
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
done < <(find "$REPO_PATH" -type f -size -1M -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | tr '\n' '\0')

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

# ============================================================
# Web3 / Blockchain Secrets
# ============================================================

# --- Web3: Hex Private Keys (0x + 64 hex chars near crypto keywords) ---
while IFS= read -r result; do
  f=$(echo "$result" | cut -d: -f1)
  ln=$(echo "$result" | cut -d: -f2)
  matched=$(echo "$result" | grep -oE '0x[0-9a-fA-F]{64}')
  # Exclude known zero/test keys
  case "$matched" in
    0x0000000000000000000000000000000000000000000000000000000000000000) continue ;;
  esac
  emit "CRITICAL" "web3_hex_private_key" "$f" "$ln" "Potential Web3 private key found (0x + 64 hex chars)" "Remove key and transfer funds to a new wallet immediately"
done < <(grep -rnEi '(private[_-]?key|secret[_-]?key|signer|wallet|account)\s*[:=]\s*["\x27]?0x[0-9a-fA-F]{64}' "$REPO_PATH" "${SOURCE_INCLUDES[@]}" 2>/dev/null || true)

# --- Web3: Hardhat / Foundry config with embedded keys ---
for cfg_file in "hardhat.config.js" "hardhat.config.ts" "foundry.toml"; do
  cfg_path="$REPO_PATH/$cfg_file"
  [[ -f "$cfg_path" ]] || continue
  while IFS= read -r result; do
    ln=$(echo "$result" | cut -d: -f1)
    emit "CRITICAL" "web3_config_private_key" "$cfg_path" "$ln" "Private key embedded in $cfg_file" "Use environment variables or a secrets manager — never commit keys in config"
  done < <(grep -nE '0x[0-9a-fA-F]{64}' "$cfg_path" 2>/dev/null || true)
done

# Also check for accounts arrays with hex keys in any JS/TS config
while IFS= read -r result; do
  f=$(echo "$result" | cut -d: -f1)
  ln=$(echo "$result" | cut -d: -f2)
  emit "CRITICAL" "web3_accounts_array_key" "$f" "$ln" "Private key in accounts array (Hardhat/Web3 config)" "Use environment variables: accounts: [process.env.PRIVATE_KEY]"
done < <(grep -rnE 'accounts\s*:\s*\[\s*["\x27]0x[0-9a-fA-F]{64}' "$REPO_PATH" "${SOURCE_INCLUDES[@]}" 2>/dev/null || true)

# --- Web3: BIP-39 Mnemonic / Seed Phrases ---
BIP39_WORDLIST="$SCRIPT_DIR/data/bip39_english.txt"
if [[ -f "$BIP39_WORDLIST" ]]; then
  # Load wordlist into associative array for O(1) lookup (requires bash 4+)
  declare -A _BIP39=()
  while IFS= read -r w; do
    _BIP39["$w"]=1
  done < "$BIP39_WORDLIST"

  # Check function: given a string of words, return 0 if >=80% match BIP-39
  _bip39_check() {
    local -a words
    read -ra words <<< "$1"
    local total=${#words[@]}
    [[ "$total" -lt 12 ]] && return 1
    # Only check first 12 or 24 words
    local check_count="$total"
    [[ "$check_count" -gt 24 ]] && check_count=24
    local hits=0
    for ((i = 0; i < check_count; i++)); do
      local lw
      lw=$(echo "${words[$i]}" | tr '[:upper:]' '[:lower:]' | tr -d '",;:')
      [[ -n "${_BIP39[$lw]+x}" ]] && hits=$((hits + 1))
    done
    local threshold=$(( (check_count * 80 + 99) / 100 ))
    [[ "$hits" -ge "$threshold" ]] && return 0
    return 1
  }

  # Hardhat default test mnemonic
  HARDHAT_TEST_MNEMONIC="test test test test test test test test test test test junk"

  # Track already-reported file:line pairs to avoid duplicates across passes
  declare -A _BIP39_REPORTED=()

  # Two-pass approach: scan lines with context clues, then validate
  while IFS= read -r result; do
    f=$(echo "$result" | cut -d: -f1)
    ln=$(echo "$result" | cut -d: -f2)
    line_content=$(echo "$result" | cut -d: -f3-)
    # Extract word sequence (lowercase first, then match)
    word_seq=$(echo "$line_content" | tr '[:upper:]' '[:lower:]' | grep -oE '[a-z]{3,}( [a-z]{3,}){11,23}' || true)
    [[ -z "$word_seq" ]] && continue
    # Skip known test mnemonics
    [[ "$word_seq" == "$HARDHAT_TEST_MNEMONIC" ]] && continue
    if _bip39_check "$word_seq"; then
      _BIP39_REPORTED["$f:$ln"]=1
      emit "CRITICAL" "web3_bip39_mnemonic" "$f" "$ln" "Potential BIP-39 mnemonic seed phrase detected" "Remove mnemonic and transfer funds to a new wallet with a fresh seed"
    fi
  done < <(grep -rnEi '(mnemonic|seed|recovery|phrase|12.?words?|24.?words?|HD_WALLET|SEED_PHRASE)' "$REPO_PATH" "${SOURCE_INCLUDES[@]}" 2>/dev/null || true)

  # Also scan for bare 12/24-word sequences in common config/env files
  # shellcheck disable=SC2094  # False positive: emit writes to stdout, not to $f
  for ext in env env.* js ts json yaml yml toml; do
    while IFS= read -r -d '' f; do
      file "$f" | grep -qE '(text|JSON)' || continue
      line_num=0
      while IFS= read -r line; do
        line_num=$((line_num + 1))
        # Skip if already reported in context-clue pass
        [[ -n "${_BIP39_REPORTED["$f:$line_num"]+x}" ]] && continue
        word_seq=$(echo "$line" | tr '[:upper:]' '[:lower:]' | grep -oE '[a-z]{3,}( [a-z]{3,}){11,23}' || true)
        [[ -z "$word_seq" ]] && continue
        [[ "$word_seq" == "$HARDHAT_TEST_MNEMONIC" ]] && continue
        if _bip39_check "$word_seq"; then
          emit "CRITICAL" "web3_bip39_mnemonic" "$f" "$line_num" "Potential BIP-39 mnemonic seed phrase detected" "Remove mnemonic and transfer funds to a new wallet with a fresh seed"
        fi
      done < "$f"
    done < <(find "$REPO_PATH" -type f -name "*.$ext" -size -1M -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | tr '\n' '\0')
  done

  unset _BIP39_REPORTED
  unset _BIP39
else
  echo "SKIPPED|web3_bip39|-|-|BIP-39 wordlist not found at $BIP39_WORDLIST|Ensure scanner data files are intact"
fi

# --- Web3: Solana Private Keys (base58, 87-88 chars near Solana keywords) ---
while IFS= read -r result; do
  f=$(echo "$result" | cut -d: -f1)
  ln=$(echo "$result" | cut -d: -f2)
  emit "CRITICAL" "web3_solana_keypair" "$f" "$ln" "Potential Solana private keypair found (base58, 87-88 chars)" "Remove keypair and generate a new wallet"
done < <(grep -rnEi '(solana|keypair|phantom|secret)\s*[:=]\s*["\x27]?[1-9A-HJ-NP-Za-km-z]{87,88}["\x27]?' "$REPO_PATH" "${SOURCE_INCLUDES[@]}" 2>/dev/null || true)

# Solana keypair JSON format: array of 64 integers (may span multiple lines)
while IFS= read -r -d '' f; do
  [[ -f "$f" ]] || continue
  # Collapse file to single line, strip whitespace, then match 64-integer array
  compact=$(tr -d '[:space:]' < "$f" 2>/dev/null) || continue
  if [[ "$compact" =~ ^\[([0-9]{1,3},){63}[0-9]{1,3}\]$ ]]; then
    emit "CRITICAL" "web3_solana_keypair_json" "$f" "-" "Potential Solana keypair JSON file (64-byte array)" "Remove keypair file and generate a new wallet"
  fi
done < <(find "$REPO_PATH" -type f -name '*.json' -size -1M -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | tr '\n' '\0')

# --- Web3: Keystore / Wallet Files ---
# File extension/name based detection
while IFS= read -r -d '' f; do
  emit "HIGH" "web3_wallet_file" "$f" "-" "Wallet/keystore file detected" "Remove wallet file — consider rotating if password was weak"
done < <(find "$REPO_PATH" -type f \( -name '*.keystore' -o -name '*.wallet' -o -name 'UTC--*' \) -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | tr '\n' '\0')

# Ethereum keystore v3 content detection (JSON with crypto+ciphertext+kdf)
while IFS= read -r -d '' f; do
  [[ -f "$f" ]] || continue
  if grep -q '"crypto"' "$f" 2>/dev/null && grep -q '"ciphertext"' "$f" 2>/dev/null && grep -q '"kdf"' "$f" 2>/dev/null; then
    emit "HIGH" "web3_keystore_content" "$f" "-" "Ethereum keystore v3 file detected (contains crypto+ciphertext+kdf)" "Remove wallet file — consider rotating if password was weak"
  fi
done < <(find "$REPO_PATH" -type f -name '*.json' -size -1M -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | tr '\n' '\0')

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
