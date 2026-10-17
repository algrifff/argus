#!/usr/bin/env bash
# Sets a repo up to use Argus: checks the Argus GitHub App is installed on it, saves the
# Claude token, app key and client ID on the repo, and opens a PR adding .github/workflows/pr.yml.
# Safe to run again: it skips whatever is already done.
#
# Usage: scripts/add-repo.sh <owner/repo> <app-private-key.pem> <app-client-id>
# Needs gh (logged in), openssl and curl. On Windows, run it from Git Bash.
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "Usage: $0 <owner/repo> <app-private-key.pem> <app-client-id>" >&2
  exit 1
fi
repo=$1 key=$2 client_id=$3
[ -f "$key" ] || { echo "No key file at $key" >&2; exit 1; }
gh repo view "$repo" --json name > /dev/null

# 1. The app must be installed on the repo, or it can't post there. Ask GitHub as the app,
#    with a 10-minute token signed by the app's private key.
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
now=$(date +%s)
unsigned="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url).$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$client_id" | b64url)"
jwt="$unsigned.$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$key" -binary | b64url)"
as_app() { curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $jwt" -H "Accept: application/vnd.github+json" "https://api.github.com$1"; }
if [ "$(as_app /app)" != 200 ]; then
  echo "✗ GitHub rejected the key. Check that the .pem and client ID belong to the same app." >&2
  exit 1
fi
case "$(as_app "/repos/$repo/installation")" in
  200) echo "✓ App is installed on $repo" ;;
  *) echo "✗ The app isn't installed on $repo. Add it under Settings → Applications → Installed GitHub Apps → Configure, then run this again." >&2; exit 1 ;;
esac

# 2. Secrets and variable.
if gh secret list -R "$repo" --json name -q '.[].name' | grep -qx CLAUDE_CODE_OAUTH_TOKEN; then
  echo "✓ CLAUDE_CODE_OAUTH_TOKEN already set"
else
  echo "Run 'claude setup-token' in another terminal, then paste the token here."
  gh secret set CLAUDE_CODE_OAUTH_TOKEN -R "$repo"
fi
gh secret set ARGUS_APP_PRIVATE_KEY -R "$repo" < "$key"
gh variable set ARGUS_APP_CLIENT_ID -R "$repo" -b "$client_id"
echo "✓ App key and client ID set"

# 3. The workflow, as a PR so you can edit it before it lands.
branch=$(gh repo view "$repo" --json defaultBranchRef -q .defaultBranchRef.name)
if gh api "repos/$repo/contents/.github/workflows/pr.yml?ref=$branch" --silent 2> /dev/null; then
  cat <<'EOF'
✓ .github/workflows/pr.yml already exists, so no PR. Make sure its review job has:
    with:
      app-client-id: ${{ vars.ARGUS_APP_CLIENT_ID }}
    secrets:
      ARGUS_APP_PRIVATE_KEY: ${{ secrets.ARGUS_APP_PRIVATE_KEY }}
EOF
  exit 0
fi

# The checks job runs package.json scripts, so only Node repos get it.
checks=""
if gh api "repos/$repo/contents/package.json?ref=$branch" --silent 2> /dev/null; then
  checks=$'  checks:\n    uses: algrifff/argus/.github/workflows/node-checks.yml@v1\n\n'
fi
workflow=$(cat <<EOF
name: pr

on:
  pull_request:
    # ready_for_review: the Claude review skips drafts, so run it when one is marked ready.
    types: [opened, synchronize, reopened, ready_for_review]

concurrency:
  group: pr-\${{ github.event.pull_request.number }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
${checks}  security:
    uses: algrifff/argus/.github/workflows/security.yml@v1

  review:
    uses: algrifff/argus/.github/workflows/agent-review.yml@v1
    permissions:
      contents: read
      pull-requests: write
    with:
      agents: security,adversarial,standards
      app-client-id: \${{ vars.ARGUS_APP_CLIENT_ID }}
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: \${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
      ARGUS_APP_PRIVATE_KEY: \${{ secrets.ARGUS_APP_PRIVATE_KEY }}
EOF
)

new=ci/argus
if ! gh api "repos/$repo/git/ref/heads/$new" --silent 2> /dev/null; then
  sha=$(gh api "repos/$repo/git/ref/heads/$branch" -q .object.sha)
  gh api "repos/$repo/git/refs" -f ref="refs/heads/$new" -f sha="$sha" --silent
fi
existing=$(gh api "repos/$repo/contents/.github/workflows/pr.yml?ref=$new" -q .sha 2> /dev/null || true)
gh api -X PUT "repos/$repo/contents/.github/workflows/pr.yml" --silent \
  -f message="ci: run PR checks and Claude review from Argus" \
  -f content="$(printf '%s\n' "$workflow" | openssl base64 -A)" \
  -f branch="$new" ${existing:+-f sha="$existing"}
if gh pr view "$new" -R "$repo" --json url -q .url 2> /dev/null; then exit 0; fi
gh pr create -R "$repo" --base "$branch" --head "$new" \
  --title "ci: run PR checks and Claude review from Argus" \
  --body "Adds \`.github/workflows/pr.yml\`, which runs [Argus](https://github.com/algrifff/argus) on every PR. Edit the jobs before merging if this repo needs different checks."
