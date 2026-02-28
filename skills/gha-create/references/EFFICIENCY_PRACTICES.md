# Efficiency Practices Reference

Detailed efficiency rules for GitHub Actions workflows. Each rule includes cost context, bad/good examples, and edge cases.

## Table of Contents

- [E1: Path Filtering](#e1-path-filtering)
- [E2: Native Caching](#e2-native-caching)
- [E3: Concurrency Control](#e3-concurrency-control)
- [E4: Matrix Optimization](#e4-matrix-optimization)

---

## E1: Path Filtering

**Rule**: Use `paths` or `paths-ignore` on `push` and `pull_request` triggers to prevent workflows from running when only irrelevant files change.

**Why**: Without path filters, every push triggers every workflow. A README typo fix runs the full CI pipeline, wasting runner minutes and blocking the merge queue. Path filtering ensures workflows only run when relevant code changes.

### Bad Example

```yaml
# BAD: Runs on every push to any file
on: [push, pull_request]
```

### Good Examples

```yaml
# GOOD: Only runs when source code or dependencies change
on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'package*.json'
      - '.github/workflows/ci.yml'
  pull_request:
    paths:
      - 'src/**'
      - 'package*.json'
      - '.github/workflows/ci.yml'

# GOOD: Inverse approach - ignore docs and configs
on:
  push:
    branches: [main]
    paths-ignore:
      - '**.md'
      - 'docs/**'
      - '.gitignore'
      - 'LICENSE'
  pull_request:
    paths-ignore:
      - '**.md'
      - 'docs/**'
```

### `paths` vs `paths-ignore`

| Approach | Use When |
|----------|----------|
| `paths` (allowlist) | Few relevant directories, clear ownership |
| `paths-ignore` (denylist) | Most files are relevant, only a few should be excluded |

**Important**: You cannot use both `paths` and `paths-ignore` on the same event.

### Monorepo Patterns

```yaml
# Run only when the frontend package changes
on:
  push:
    paths:
      - 'packages/frontend/**'
      - 'packages/shared/**'  # Shared deps affect frontend too
      - '.github/workflows/frontend-ci.yml'
```

### When NOT to Use Path Filtering

- **Deployment workflows**: Every push to `main` should trigger deployment
- **Security scanning**: Security scans should run on all changes
- **Release workflows**: Release creation should not be skipped
- **Dependency update workflows**: `dependabot.yml` triggers should run fully

---

## E2: Native Caching

**Rule**: Every `setup-*` action should enable its built-in `cache` parameter. Do not use a separate `actions/cache` step when native caching is available.

**Why**: Setup actions (setup-node, setup-python, etc.) have built-in caching that automatically generates appropriate cache keys and restores dependencies. Using a separate `actions/cache` step is more verbose, requires manual key management, and is more error-prone.

### Bad Example

```yaml
# BAD: Separate cache step - verbose and manual key management
- uses: actions/cache@cdf6c1fa76f9f475f3d7449005a359c84ca0f306 # v5.0.3
  with:
    path: ~/.npm
    key: ${{ runner.os }}-npm-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-npm-
- uses: actions/setup-node@6044e13b5dc448c55e2357c09f80417699197238 # v6.2.0
  with:
    node-version: 20
```

### Good Example

```yaml
# GOOD: Built-in cache - one step, automatic key
- uses: actions/setup-node@6044e13b5dc448c55e2357c09f80417699197238 # v6.2.0
  with:
    node-version: 20
    cache: 'npm'
```

### Setup Action Cache Parameters

| Action | Cache Parameter | Values |
|--------|----------------|--------|
| `actions/setup-node` | `cache` | `'npm'`, `'yarn'`, `'pnpm'` |
| `actions/setup-python` | `cache` | `'pip'`, `'pipenv'`, `'poetry'` |
| `actions/setup-go` | `cache` | `true` (boolean) |
| `actions/setup-java` | `cache` | `'maven'`, `'gradle'`, `'sbt'` |

### Custom Cache Keys for Monorepos

When the default cache key does not capture all relevant files (e.g., monorepos with multiple lock files):

```yaml
- uses: actions/setup-node@6044e13b5dc448c55e2357c09f80417699197238 # v6.2.0
  with:
    node-version: 20
    cache: 'npm'
    cache-dependency-path: 'packages/frontend/package-lock.json'
```

### Docker Layer Caching

For Docker builds, use GitHub Actions cache backend instead of `actions/cache`:

```yaml
- uses: docker/build-push-action@4f58ea79222b3b9dc2c8bbdd6debcef730109a75 # v6.9.0
  with:
    context: .
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

---

## E3: Concurrency Control

**Rule**: Add a `concurrency` group with `cancel-in-progress: true` to prevent redundant workflow runs from wasting runner minutes.

**Why**: When a developer pushes 5 commits in quick succession, GitHub Actions starts 5 workflow runs. Without concurrency control, all 5 run to completion even though only the last one matters. Concurrency groups cancel obsolete runs automatically.

### Bad Example

```yaml
# BAD: No concurrency control - 5 pushes = 5 full pipeline runs
name: CI
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    runs-on: ubuntu-latest
```

### Good Examples

```yaml
# GOOD: Cancel redundant runs on the same branch
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

# GOOD: Include workflow name for repos with many workflows
concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

### Group Naming Patterns

| Pattern | Use Case |
|---------|----------|
| `${{ github.workflow }}-${{ github.ref }}` | Standard — per-workflow, per-branch |
| `deploy-production` | Fixed group — only one deploy at a time |
| `${{ github.workflow }}-${{ github.event.pull_request.number }}` | PR-specific — cancel only within same PR |

### Deployment Exception

Deployment workflows should NOT cancel in-progress runs. Cancelling a deploy mid-execution can leave infrastructure in an inconsistent state.

```yaml
# GOOD: Deployment concurrency - queue, don't cancel
concurrency:
  group: deploy-production
  cancel-in-progress: false  # Never cancel an in-progress deployment
```

### Queue Behavior

When `cancel-in-progress: false` is set:
- A pending run waits for the current run to finish
- If multiple runs are pending, only the latest one is kept — earlier pending runs are cancelled
- This means at most one running + one pending at any time

---

## E4: Matrix Optimization

**Rule**: When using `strategy.matrix`, keep `fail-fast: true` (the default) and use `include`/`exclude` to prune unnecessary combinations.

**Why**: Without `fail-fast`, all matrix jobs run to completion even after the first failure. If you have a 3x3 matrix (9 jobs) and the first job fails at minute 2, the remaining 8 jobs continue running for their full duration. With `fail-fast: true`, the remaining jobs are cancelled as soon as one fails.

### Bad Example

```yaml
# BAD: fail-fast disabled - all 9 jobs run even if one fails
strategy:
  fail-fast: false
  matrix:
    node-version: [18, 20, 22]
    os: [ubuntu-latest, macos-latest, windows-latest]
```

### Good Examples

```yaml
# GOOD: fail-fast is true by default, but explicit is clearer
strategy:
  fail-fast: true
  matrix:
    node-version: [18, 20, 22]

# GOOD: Exclude unnecessary combinations
strategy:
  fail-fast: true
  matrix:
    os: [ubuntu-latest, macos-latest, windows-latest]
    node-version: [18, 20, 22]
    exclude:
      - os: windows-latest
        node-version: 18  # Don't test old Node on Windows

# GOOD: Include specific additional combinations
strategy:
  fail-fast: true
  matrix:
    node-version: [20]
    include:
      - node-version: 22
        experimental: true  # Test Node 22 but allow failure
```

### Dynamic Matrix

For advanced use cases, generate the matrix dynamically:

```yaml
jobs:
  matrix-setup:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.set-matrix.outputs.matrix }}
    steps:
      - id: set-matrix
        run: echo "matrix={\"node-version\":[18,20,22]}" >> "$GITHUB_OUTPUT"

  test:
    needs: matrix-setup
    strategy:
      fail-fast: true
      matrix: ${{ fromJson(needs.matrix-setup.outputs.matrix) }}
```

### `max-parallel` for Cost Control

Limit concurrent jobs when runner capacity or costs are a concern:

```yaml
strategy:
  fail-fast: true
  max-parallel: 3  # Run at most 3 matrix jobs simultaneously
  matrix:
    node-version: [18, 20, 22]
    os: [ubuntu-latest, macos-latest, windows-latest]
```
