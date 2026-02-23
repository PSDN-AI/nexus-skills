#!/usr/bin/env bash
# test_check_secrets.sh — Tests for check_secrets.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANNER_DIR="${1:?Usage: test_check_secrets.sh <scanner_dir>}"

# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

CHECK="$SCANNER_DIR/check_secrets.sh"

# ============================================================
# .env file detection
# ============================================================

test_env_file_detected() {
  setup_fixture_dir
  create_file_ln ".env" "API_KEY=abc123secret"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "CRITICAL|env_file" "detects .env file"
  teardown_fixture_dir
}

test_env_dotenv_variant_detected() {
  setup_fixture_dir
  create_file_ln ".env.production" "DB_PASSWORD=secret"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "CRITICAL|env_file" "detects .env.production"
  teardown_fixture_dir
}

test_env_example_excluded() {
  setup_fixture_dir
  create_file_ln ".env.example" "API_KEY=your-key-here"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "env_file" ".env.example excluded"
  teardown_fixture_dir
}

test_env_sample_excluded() {
  setup_fixture_dir
  create_file_ln ".env.sample" "API_KEY=your-key-here"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "env_file" ".env.sample excluded"
  teardown_fixture_dir
}

test_env_template_excluded() {
  setup_fixture_dir
  create_file_ln ".env.template" "API_KEY=your-key-here"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "env_file" ".env.template excluded"
  teardown_fixture_dir
}

# ============================================================
# Private key files
# ============================================================

test_pem_file_detected() {
  setup_fixture_dir
  create_file "server.pem" "dummy cert"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "CRITICAL|private_key_file" "detects .pem file"
  teardown_fixture_dir
}

test_id_rsa_detected() {
  setup_fixture_dir
  create_file "id_rsa" "dummy key"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "CRITICAL|private_key_file" "detects id_rsa"
  teardown_fixture_dir
}

test_p12_file_detected() {
  setup_fixture_dir
  create_file "cert.p12" "dummy cert"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "CRITICAL|private_key_file" "detects .p12 file"
  teardown_fixture_dir
}

# ============================================================
# Private key content
# ============================================================

test_rsa_private_key_content_detected() {
  setup_fixture_dir
  # Use .py extension so macOS 'file' identifies it as text (not PEM)
  create_file_ln "config.py" "# Configuration file
KEY_DATA = \"\"\"
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA
-----END RSA PRIVATE KEY-----
\"\"\""
  run_check "$CHECK"
  assert_contains "$OUTPUT" "CRITICAL|private_key_content" "detects RSA private key content"
  teardown_fixture_dir
}

test_ec_private_key_content_detected() {
  setup_fixture_dir
  create_file_ln "key.py" "# Key loader
KEY = \"\"\"
-----BEGIN EC PRIVATE KEY-----
MHQCAQEEIBkg
-----END EC PRIVATE KEY-----
\"\"\""
  run_check "$CHECK"
  assert_contains "$OUTPUT" "CRITICAL|private_key_content" "detects EC private key content"
  teardown_fixture_dir
}

test_public_key_not_flagged() {
  setup_fixture_dir
  create_file_ln "pubkey.py" "# Public key
KEY = \"\"\"
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
-----END PUBLIC KEY-----
\"\"\""
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "private_key_content" "public key not flagged"
  teardown_fixture_dir
}

# ============================================================
# AWS credentials
# ============================================================

test_aws_akia_detected() {
  setup_fixture_dir
  create_file_ln "deploy.py" "aws_key = 'AKIAIOSFODNN7EXAMPLE'"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "CRITICAL|aws_credentials" "detects AWS AKIA pattern"
  teardown_fixture_dir
}

test_aws_secret_key_detected() {
  setup_fixture_dir
  create_file_ln "config.yml" "aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "CRITICAL|aws_credentials" "detects aws_secret_access_key"
  teardown_fixture_dir
}

# ============================================================
# Generic hardcoded secrets
# ============================================================

test_api_key_assignment_detected() {
  setup_fixture_dir
  # Use double quotes — macOS BSD grep doesn't support \x27 for single quote
  create_file_ln "app.js" 'const api_key = "sk_live_abcdefgh12345678";'
  run_check "$CHECK"
  assert_contains "$OUTPUT" "HIGH|hardcoded_secret" "detects api_key assignment"
  teardown_fixture_dir
}

test_password_assignment_detected() {
  setup_fixture_dir
  create_file_ln "app.py" 'password: "MyS3cretPassw0rd0xyz1"'
  run_check "$CHECK"
  assert_contains "$OUTPUT" "HIGH|hardcoded_secret" "detects password assignment"
  teardown_fixture_dir
}

test_short_value_not_flagged() {
  setup_fixture_dir
  create_file_ln "app.js" 'const api_key = "short";'
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "hardcoded_secret" "short value (<8 chars) not flagged"
  teardown_fixture_dir
}

# ============================================================
# Hardcoded IPs
# ============================================================

test_private_ip_detected() {
  setup_fixture_dir
  create_file_ln "config.yaml" "host: 10.0.1.50"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "HIGH|hardcoded_ip" "detects private IP"
  teardown_fixture_dir
}

test_localhost_excluded() {
  setup_fixture_dir
  create_file_ln "config.yaml" "host: 127.0.0.1"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "hardcoded_ip" "127.0.0.1 excluded"
  teardown_fixture_dir
}

test_zero_ip_excluded() {
  setup_fixture_dir
  create_file_ln "config.yaml" "bind: 0.0.0.0"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "hardcoded_ip" "0.0.0.0 excluded"
  teardown_fixture_dir
}

# ============================================================
# PII — emails
# ============================================================

test_personal_email_detected() {
  setup_fixture_dir
  create_file_ln "README.md" "Contact: john@acme.com for support"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "HIGH|pii_email" "detects personal email"
  teardown_fixture_dir
}

test_example_email_excluded() {
  setup_fixture_dir
  create_file_ln "README.md" "Use user@example.com as a placeholder"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "pii_email" "example.com email excluded"
  teardown_fixture_dir
}

test_noreply_email_excluded() {
  setup_fixture_dir
  create_file_ln "README.md" "bot@users.noreply.github.com"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "pii_email" "noreply email excluded"
  teardown_fixture_dir
}

# ============================================================
# GitHub Actions
# ============================================================

test_actions_hardcoded_secret_detected() {
  setup_fixture_dir
  mkdir -p "$FIXTURE_REPO/.github/workflows"
  # Use double quotes — macOS BSD grep doesn't support \x27
  create_file_ln ".github/workflows/ci.yml" 'name: CI
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo done
        env:
          token: "ghp_abc123defg456hijklmnop"'
  run_check "$CHECK"
  assert_contains "$OUTPUT" "CRITICAL|actions_hardcoded_secret" "detects hardcoded secret in GH Actions"
  teardown_fixture_dir
}

test_actions_script_injection_detected() {
  setup_fixture_dir
  mkdir -p "$FIXTURE_REPO/.github/workflows"
  # shellcheck disable=SC2016  # Single quotes intentional — we want literal ${{
  create_file_ln ".github/workflows/ci.yml" 'name: CI
on: issues
jobs:
  greet:
    runs-on: ubuntu-latest
    steps:
      - run: echo "${{ github.event.issue.title }}"'
  run_check "$CHECK"
  assert_contains "$OUTPUT" "HIGH|actions_script_injection" "detects GH Actions script injection"
  teardown_fixture_dir
}

# ============================================================
# Web3 — Hex private keys
# ============================================================

test_web3_hex_key_detected() {
  setup_fixture_dir
  create_file_ln "deploy.ts" 'const private_key = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";'
  run_check "$CHECK"
  assert_contains "$OUTPUT" "CRITICAL|web3_hex_private_key" "detects Web3 hex private key"
  teardown_fixture_dir
}

test_web3_zero_key_excluded() {
  setup_fixture_dir
  create_file_ln "deploy.ts" 'const private_key = "0x0000000000000000000000000000000000000000000000000000000000000000";'
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "web3_hex_private_key" "zero key excluded"
  teardown_fixture_dir
}

# ============================================================
# Web3 — Hardhat/Foundry config
# ============================================================

test_hardhat_config_key_detected() {
  setup_fixture_dir
  create_file_ln "hardhat.config.js" "module.exports = {
  networks: {
    mainnet: {
      url: 'https://mainnet.infura.io',
      accounts: ['0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80']
    }
  }
};"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "CRITICAL|web3_config_private_key" "detects key in hardhat.config.js"
  teardown_fixture_dir
}

# ============================================================
# Web3 — BIP-39 mnemonic
# ============================================================

test_bip39_mnemonic_detected() {
  setup_fixture_dir
  # 12 valid BIP-39 words with context clue
  create_file_ln "seed.sh" "MNEMONIC='abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about'"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "CRITICAL|web3_bip39_mnemonic" "detects BIP-39 mnemonic"
  teardown_fixture_dir
}

test_hardhat_test_mnemonic_excluded() {
  setup_fixture_dir
  create_file_ln "test.sh" "MNEMONIC='test test test test test test test test test test test junk'"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "web3_bip39_mnemonic" "Hardhat test mnemonic excluded"
  teardown_fixture_dir
}

test_bip39_non_matching_words_excluded() {
  setup_fixture_dir
  create_file_ln "note.sh" "MNEMONIC='foo bar baz qux zap zig zog zug zum zep zip zop'"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "web3_bip39_mnemonic" "non-BIP-39 words excluded"
  teardown_fixture_dir
}

# ============================================================
# Web3 — Solana keypair JSON
# ============================================================

test_solana_keypair_json_detected() {
  setup_fixture_dir
  # Create a 64-integer JSON array (all values 0-255)
  local arr="["
  for i in $(seq 0 63); do
    [[ "$i" -gt 0 ]] && arr+=","
    arr+="$((i % 256))"
  done
  arr+="]"
  create_file "keypair.json" "$arr"
  # Debug: verify fixture exists and show file info
  echo "    [debug] fixture: $FIXTURE_REPO/keypair.json exists=$(test -f "$FIXTURE_REPO/keypair.json" && echo yes || echo no)" >&2
  echo "    [debug] file cmd: $(file "$FIXTURE_REPO/keypair.json" 2>&1)" >&2
  echo "    [debug] find json: $(find "$FIXTURE_REPO" -name '*.json' -not -path '*/.git/*' 2>&1)" >&2
  run_check "$CHECK"
  echo "    [debug] EXIT_CODE=$EXIT_CODE STDERR=$STDERR" >&2
  assert_contains "$OUTPUT" "CRITICAL|web3_solana_keypair_json" "detects Solana keypair JSON"
  teardown_fixture_dir
}

# ============================================================
# Web3 — Wallet/keystore files
# ============================================================

test_wallet_keystore_file_detected() {
  setup_fixture_dir
  create_file "my.keystore" "dummy keystore"
  run_check "$CHECK"
  assert_contains "$OUTPUT" "HIGH|web3_wallet_file" "detects .keystore file"
  teardown_fixture_dir
}

test_ethereum_keystore_v3_detected() {
  setup_fixture_dir
  create_file_ln "wallet.json" '{
  "crypto": {
    "ciphertext": "abc123",
    "kdf": "scrypt"
  }
}'
  # Debug: verify fixture
  echo "    [debug] wallet.json exists=$(test -f "$FIXTURE_REPO/wallet.json" && echo yes || echo no)" >&2
  echo "    [debug] content: $(cat "$FIXTURE_REPO/wallet.json")" >&2
  echo "    [debug] grep crypto: $(grep -c '"crypto"' "$FIXTURE_REPO/wallet.json" 2>&1)" >&2
  run_check "$CHECK"
  echo "    [debug] EXIT_CODE=$EXIT_CODE STDERR=$STDERR" >&2
  assert_contains "$OUTPUT" "HIGH|web3_keystore_content" "detects Ethereum keystore v3 content"
  teardown_fixture_dir
}

# ============================================================
# gitleaks integration
# ============================================================

test_gitleaks_handling() {
  setup_fixture_dir
  create_file_ln "app.py" "x = 1"
  run_check "$CHECK"
  if command -v gitleaks &>/dev/null && command -v jq &>/dev/null; then
    assert_not_contains "$OUTPUT" "SKIPPED|gitleaks" "gitleaks runs when installed"
  elif command -v gitleaks &>/dev/null; then
    assert_contains "$OUTPUT" "SKIPPED|gitleaks_jq" "gitleaks SKIPPED (jq missing)"
  else
    assert_contains "$OUTPUT" "SKIPPED|gitleaks" "gitleaks SKIPPED when not installed"
  fi
  teardown_fixture_dir
}

# ============================================================
# Clean repo — no findings
# ============================================================

test_clean_repo_no_findings() {
  setup_fixture_dir
  create_file_ln "README.md" "# Clean Project"
  create_file_ln "main.py" "def main():
    print('hello')"
  run_check "$CHECK"
  assert_not_contains "$OUTPUT" "CRITICAL" "clean repo has no CRITICAL findings"
  assert_not_contains "$OUTPUT" "HIGH" "clean repo has no HIGH findings"
  teardown_fixture_dir
}

# ============================================================
# Run all tests
# ============================================================

echo ">> check_secrets.sh"
test_env_file_detected
test_env_dotenv_variant_detected
test_env_example_excluded
test_env_sample_excluded
test_env_template_excluded
test_pem_file_detected
test_id_rsa_detected
test_p12_file_detected
test_rsa_private_key_content_detected
test_ec_private_key_content_detected
test_public_key_not_flagged
test_aws_akia_detected
test_aws_secret_key_detected
test_api_key_assignment_detected
test_password_assignment_detected
test_short_value_not_flagged
test_private_ip_detected
test_localhost_excluded
test_zero_ip_excluded
test_personal_email_detected
test_example_email_excluded
test_noreply_email_excluded
test_actions_hardcoded_secret_detected
test_actions_script_injection_detected
test_web3_hex_key_detected
test_web3_zero_key_excluded
test_hardhat_config_key_detected
test_bip39_mnemonic_detected
test_hardhat_test_mnemonic_excluded
test_bip39_non_matching_words_excluded
test_solana_keypair_json_detected
test_wallet_keystore_file_detected
test_ethereum_keystore_v3_detected
test_gitleaks_handling
test_clean_repo_no_findings
print_summary
