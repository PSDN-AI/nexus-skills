# SHA Lookup Guide

How to find the current commit SHA for any GitHub Action, so you can pin it in your workflows.

## Table of Contents

- [Method 1: gh CLI](#method-1-gh-cli)
- [Method 2: git ls-remote](#method-2-git-ls-remote)
- [Method 3: GitHub UI](#method-3-github-ui)
- [Bulk Lookup Script](#bulk-lookup-script)
- [Common Actions Reference](#common-actions-reference)
- [Keeping SHAs Updated](#keeping-shas-updated)

---

## Method 1: gh CLI

Look up the SHA for a specific release tag:

```bash
# Get the latest release tag
TAG=$(gh api repos/actions/checkout/releases/latest --jq '.tag_name')
echo "$TAG"

# Get the commit SHA for that tag
SHA=$(gh api repos/actions/checkout/git/ref/tags/"$TAG" --jq '.object.sha')
echo "$SHA"

# One-liner: get latest release SHA
gh api repos/actions/checkout/releases/latest --jq '.tag_name' | \
  xargs -I {} gh api repos/actions/checkout/git/ref/tags/{} --jq '.object.sha'
```

**Note**: Some tags are annotated (point to a tag object, not a commit). If the `object.type` is `tag`, dereference it:

```bash
REF=$(gh api repos/actions/checkout/git/ref/tags/v6.0.2)
TYPE=$(echo "$REF" | jq -r '.object.type')
SHA=$(echo "$REF" | jq -r '.object.sha')

if [ "$TYPE" = "tag" ]; then
  # Dereference annotated tag to get the commit SHA
  SHA=$(gh api repos/actions/checkout/git/tags/"$SHA" --jq '.object.sha')
fi
echo "$SHA"
```

## Method 2: git ls-remote

One-liner that works without `gh`:

```bash
git ls-remote --tags https://github.com/actions/checkout refs/tags/v6.0.2
```

Output:
```
de0fac2e4500dabe0009e67214ff5f5447ce83dd	refs/tags/v6.0.2
```

The first column is the SHA.

## Method 3: GitHub UI

1. Navigate to the action repository (e.g., `https://github.com/actions/checkout`)
2. Click **Releases** in the right sidebar
3. Click the tag name (e.g., `v6.0.2`)
4. The commit SHA is shown in the tag details — copy the full 40-character hash

## Bulk Lookup Script

Look up SHAs for multiple actions at once:

```bash
#!/usr/bin/env bash
# Usage: ./lookup_shas.sh actions/checkout@v6.0.2 actions/setup-node@v6.2.0

for entry in "$@"; do
  REPO="${entry%%@*}"
  TAG="${entry##*@}"
  SHA=$(git ls-remote --tags "https://github.com/$REPO" "refs/tags/$TAG" | awk '{print $1}')
  if [ -n "$SHA" ]; then
    printf "- uses: %s@%s # %s\n" "$REPO" "$SHA" "$TAG"
  else
    printf "# ERROR: Could not resolve %s@%s\n" "$REPO" "$TAG" >&2
  fi
done
```

Example:
```bash
./lookup_shas.sh actions/checkout@v6.0.2 actions/setup-node@v6.2.0
```

Output:
```yaml
- uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
- uses: actions/setup-node@6044e13b5dc448c55e2357c09f80417699197238 # v6.2.0
```

## Common Actions Reference

**SHAs change with every release. Always verify before using. This table is a starting point, not a source of truth.**

| Action | Tag | SHA | Verified |
|--------|-----|-----|----------|
| `actions/checkout` | v6.0.2 | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` | 2026-02-28 |
| `actions/setup-node` | v6.2.0 | `6044e13b5dc448c55e2357c09f80417699197238` | 2026-02-28 |
| `actions/setup-python` | v6.2.0 | `a309ff8b426b58ec0e2a45f0f869d46889d02405` | 2026-02-28 |
| `actions/setup-go` | v6.3.0 | `4b73464bb391d4059bd26b0524d20df3927bd417` | 2026-02-28 |
| `actions/setup-java` | v5.2.0 | `be666c2fcd27ec809703dec50e508c2fdc7f6654` | 2026-02-28 |
| `actions/upload-artifact` | v7.0.0 | `bbbca2ddaa5d8feaa63e36b76fdaad77386f024f` | 2026-02-28 |
| `actions/download-artifact` | v8.0.0 | `70fc10c6e5e1ce46ad2ea6f2b72d43f7d47b13c3` | 2026-02-28 |
| `actions/cache` | v5.0.3 | `cdf6c1fa76f9f475f3d7449005a359c84ca0f306` | 2026-02-28 |
| `docker/setup-buildx-action` | v3.9.0 | `f7ce87c1d6bead3e36075b2ce75da1f6cc28aaca` | 2026-02-28 |
| `docker/login-action` | v3.7.0 | `c94ce9fb468520275223c153574b00df6fe4bcc9` | 2026-02-28 |
| `docker/build-push-action` | v6.9.0 | `4f58ea79222b3b9dc2c8bbdd6debcef730109a75` | 2026-02-28 |
| `aws-actions/configure-aws-credentials` | v6.0.0 | `8df5847569e6427dd6c4fb1cf565c83acfa8afa7` | 2026-02-28 |
| `google-github-actions/auth` | v3.0.0 | `7c6bc770dae815cd3e89ee6cdf493a5fab2cc093` | 2026-02-28 |
| `azure/login` | v2.3.0 | `eec3c95657c1536435858eda1f3ff5437fee8474` | 2026-02-28 |

## Keeping SHAs Updated

### Dependabot

Add to `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

Dependabot will open PRs to update action SHA pins when new versions are released.

### Renovate

Add to `renovate.json`:

```json
{
  "extends": ["config:recommended"],
  "github-actions": {
    "enabled": true
  }
}
```

### Manual Process

Run the bulk lookup script periodically to check for updates:

```bash
# Check if your current SHAs are still the latest
git ls-remote --tags https://github.com/actions/checkout | grep -E 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$' | tail -1
```
