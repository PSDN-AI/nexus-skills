#!/usr/bin/env bash
# check_code_quality.sh — Code Quality dimension: linting, TODOs, dependency vulnerabilities
# Output format: SEVERITY|CHECK|FILE|LINE|DESCRIPTION|REMEDIATION
set -euo pipefail

REPO_PATH="${1:?Usage: check_code_quality.sh <repo_path>}"

HAS_JQ=false
command -v jq &>/dev/null && HAS_JQ=true

emit() {
  echo "$1|$2|$3|$4|$5|$6"
}

# --- TODO / FIXME / HACK comments ---
while IFS= read -r result; do
  f=$(echo "$result" | cut -d: -f1)
  ln=$(echo "$result" | cut -d: -f2)
  snippet=$(echo "$result" | cut -d: -f3- | sed 's/|/∣/g' | head -c 120)
  emit "LOW" "todo_comment" "$f" "$ln" "TODO/FIXME/HACK comment: ${snippet}" "Resolve or remove before public release"
done < <(grep -rnEi '\b(TODO|FIXME|HACK|XXX)\b' "$REPO_PATH" \
  --include='*.sh' --include='*.py' --include='*.js' --include='*.ts' \
  --include='*.jsx' --include='*.tsx' --include='*.go' --include='*.rb' \
  --include='*.java' --include='*.rs' --include='*.c' --include='*.cpp' \
  --include='*.h' --include='*.hpp' --include='*.css' --include='*.scss' \
  --include='*.vue' --include='*.svelte' \
  --exclude-dir='.git' --exclude-dir='node_modules' \
  2>/dev/null | grep -v '/repo-public-readiness/scripts/' || true)

# --- shellcheck (if available) ---
if command -v shellcheck &>/dev/null; then
  if [[ "$HAS_JQ" == "true" ]]; then
    while IFS= read -r -d '' f; do
      while IFS= read -r sc_line; do
        ln=$(echo "$sc_line" | jq -r '.line // "-"')
        level=$(echo "$sc_line" | jq -r '.level // "warning"')
        msg=$(echo "$sc_line" | jq -r '.message // "shellcheck issue"')
        code=$(echo "$sc_line" | jq -r '.code // ""')
        sev="MEDIUM"
        [[ "$level" == "error" ]] && sev="HIGH"
        [[ "$level" == "info" || "$level" == "style" ]] && sev="LOW"
        emit "$sev" "shellcheck_${code}" "$f" "$ln" "shellcheck: $msg" "Fix per shellcheck SC${code} recommendation"
      done < <(shellcheck -f json "$f" 2>/dev/null | jq -c '.[]' 2>/dev/null || true)
    done < <(find "$REPO_PATH" -type f -name '*.sh' 2>/dev/null | tr '\n' '\0')
  else
    echo "SKIPPED|shellcheck_jq|-|-|jq not installed — cannot parse shellcheck JSON output|Install: brew install jq"
  fi
else
  echo "SKIPPED|shellcheck|-|-|shellcheck not installed — bash scripts not linted|Install: brew install shellcheck"
fi

# --- npm audit (if package.json exists) ---
if [[ -f "$REPO_PATH/package.json" ]]; then
  if command -v npm &>/dev/null; then
    if [[ "$HAS_JQ" == "true" ]]; then
      audit_output="$(cd "$REPO_PATH" && npm audit --json 2>/dev/null)" || true
      vuln_count=$(echo "$audit_output" | jq '.metadata.vulnerabilities.high // 0')
      crit_count=$(echo "$audit_output" | jq '.metadata.vulnerabilities.critical // 0')
      if [[ "$crit_count" -gt 0 ]]; then
        emit "HIGH" "npm_audit" "$REPO_PATH/package.json" "-" "$crit_count critical npm vulnerabilities found" "Run npm audit fix or update dependencies"
      elif [[ "$vuln_count" -gt 0 ]]; then
        emit "HIGH" "npm_audit" "$REPO_PATH/package.json" "-" "$vuln_count high npm vulnerabilities found" "Run npm audit fix or update dependencies"
      fi
    else
      echo "SKIPPED|npm_audit_jq|-|-|jq not installed — cannot parse npm audit JSON output|Install: brew install jq"
    fi
  else
    echo "SKIPPED|npm_audit|-|-|npm not installed — JS dependencies not audited|Install Node.js"
  fi
fi

# --- pip-audit (if requirements.txt exists) ---
if [[ -f "$REPO_PATH/requirements.txt" ]]; then
  if command -v pip-audit &>/dev/null; then
    if [[ "$HAS_JQ" == "true" ]]; then
      vuln_output=$(pip-audit -r "$REPO_PATH/requirements.txt" --format json 2>/dev/null || true)
      vuln_count=$(echo "$vuln_output" | jq 'length')
      if [[ "$vuln_count" -gt 0 ]]; then
        emit "HIGH" "pip_audit" "$REPO_PATH/requirements.txt" "-" "$vuln_count Python dependency vulnerabilities found" "Run pip-audit and update affected packages"
      fi
    else
      echo "SKIPPED|pip_audit_jq|-|-|jq not installed — cannot parse pip-audit JSON output|Install: brew install jq"
    fi
  else
    echo "SKIPPED|pip_audit|-|-|pip-audit not installed — Python dependencies not audited|Install: pip install pip-audit"
  fi
fi

# --- trivy (if available) ---
if command -v trivy &>/dev/null; then
  if [[ "$HAS_JQ" == "true" ]]; then
    trivy_output=$(trivy fs --format json --severity HIGH,CRITICAL "$REPO_PATH" 2>/dev/null || true)
    vuln_count=$(echo "$trivy_output" | jq '[.Results[]?.Vulnerabilities // [] | length] | add // 0')
    if [[ "$vuln_count" -gt 0 ]]; then
      emit "HIGH" "trivy_scan" "$REPO_PATH" "-" "$vuln_count high/critical vulnerabilities found by trivy" "Run trivy fs and remediate findings"
    fi
  else
    echo "SKIPPED|trivy_jq|-|-|jq not installed — cannot parse trivy JSON output|Install: brew install jq"
  fi
else
  echo "SKIPPED|trivy|-|-|trivy not installed — filesystem vulnerability scan skipped|Install: brew install trivy"
fi

# --- Python project detection ---
# A repo is a Python project if it has .py files AND a project manifest
IS_PYTHON=false
if [[ -f "$REPO_PATH/pyproject.toml" || -f "$REPO_PATH/setup.py" \
   || -f "$REPO_PATH/setup.cfg" || -f "$REPO_PATH/requirements.txt" ]]; then
  py_count=$(find "$REPO_PATH" -type f -name '*.py' \
    -not -path '*/.git/*' -not -path '*/node_modules/*' \
    -not -path '*/__pycache__/*' 2>/dev/null | head -1 | wc -l)
  if [[ "$py_count" -gt 0 ]]; then
    IS_PYTHON=true
  fi
fi

if [[ "$IS_PYTHON" == "true" ]]; then

  # --- Python linter configuration (ruff / flake8 / pylint) ---
  has_linter=false

  # Standalone config files
  for cfg in ruff.toml .ruff.toml .flake8 .pylintrc pylintrc; do
    if [[ -f "$REPO_PATH/$cfg" ]]; then
      has_linter=true
      break
    fi
  done

  # pyproject.toml sections
  if [[ "$has_linter" == "false" && -f "$REPO_PATH/pyproject.toml" ]]; then
    if grep -qE '^\[tool\.(ruff|pylint|flake8)\b' "$REPO_PATH/pyproject.toml" 2>/dev/null; then
      has_linter=true
    fi
  fi

  # setup.cfg sections
  if [[ "$has_linter" == "false" && -f "$REPO_PATH/setup.cfg" ]]; then
    if grep -qE '^\[(flake8|pylint)\b' "$REPO_PATH/setup.cfg" 2>/dev/null; then
      has_linter=true
    fi
  fi

  # Pre-commit hooks
  if [[ "$has_linter" == "false" && -f "$REPO_PATH/.pre-commit-config.yaml" ]]; then
    if grep -qE '\b(ruff|flake8|pylint)\b' "$REPO_PATH/.pre-commit-config.yaml" 2>/dev/null; then
      has_linter=true
    fi
  fi

  # Dependencies (requirements files or pyproject.toml)
  if [[ "$has_linter" == "false" ]]; then
    for req in "$REPO_PATH"/requirements*.txt; do
      if [[ -f "$req" ]] && grep -qEi '^(ruff|flake8|pylint)\b' "$req" 2>/dev/null; then
        has_linter=true
        break
      fi
    done
  fi
  if [[ "$has_linter" == "false" && -f "$REPO_PATH/pyproject.toml" ]]; then
    if grep -qEi '^\s*(ruff|flake8|pylint)\s*=' "$REPO_PATH/pyproject.toml" 2>/dev/null; then
      has_linter=true
    fi
  fi

  if [[ "$has_linter" == "false" ]]; then
    emit "LOW" "python_no_linter" "$REPO_PATH" "-" \
      "Python project has no linter configured (ruff, flake8, or pylint)" \
      "Add ruff — fast, comprehensive, replaces flake8+isort+pyflakes. See https://docs.astral.sh/ruff/"
  fi

  # --- Python type checker configuration (mypy / pyright / pytype) ---
  has_typechecker=false

  # Standalone config files
  for cfg in mypy.ini .mypy.ini pyrightconfig.json pyrightconfig.yaml; do
    if [[ -f "$REPO_PATH/$cfg" ]]; then
      has_typechecker=true
      break
    fi
  done

  # pyproject.toml sections
  if [[ "$has_typechecker" == "false" && -f "$REPO_PATH/pyproject.toml" ]]; then
    if grep -qE '^\[tool\.(mypy|pyright|pytype)\b' "$REPO_PATH/pyproject.toml" 2>/dev/null; then
      has_typechecker=true
    fi
  fi

  # setup.cfg sections
  if [[ "$has_typechecker" == "false" && -f "$REPO_PATH/setup.cfg" ]]; then
    if grep -qE '^\[mypy\b' "$REPO_PATH/setup.cfg" 2>/dev/null; then
      has_typechecker=true
    fi
  fi

  # Pre-commit hooks
  if [[ "$has_typechecker" == "false" && -f "$REPO_PATH/.pre-commit-config.yaml" ]]; then
    if grep -qE '\b(mypy|pyright|pytype)\b' "$REPO_PATH/.pre-commit-config.yaml" 2>/dev/null; then
      has_typechecker=true
    fi
  fi

  # Dependencies
  if [[ "$has_typechecker" == "false" ]]; then
    for req in "$REPO_PATH"/requirements*.txt; do
      if [[ -f "$req" ]] && grep -qEi '^(mypy|pyright|pytype)\b' "$req" 2>/dev/null; then
        has_typechecker=true
        break
      fi
    done
  fi
  if [[ "$has_typechecker" == "false" && -f "$REPO_PATH/pyproject.toml" ]]; then
    if grep -qEi '^\s*(mypy|pyright|pytype)\s*=' "$REPO_PATH/pyproject.toml" 2>/dev/null; then
      has_typechecker=true
    fi
  fi

  if [[ "$has_typechecker" == "false" ]]; then
    emit "LOW" "python_no_typechecker" "$REPO_PATH" "-" \
      "Python project has no type checker configured (mypy, pyright, or pytype)" \
      "Add mypy or pyright for static type checking to catch bugs early. See https://mypy.readthedocs.io/"
  fi

fi

exit 0
