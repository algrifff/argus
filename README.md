# Argus

Argus runs tests, lint, security scans and Claude code-review agents on every pull request (PR) in your GitHub repos. You add one workflow file to a repo and pick the checks you want.

## Quick start

> You need: a GitHub repo, plus the [GitHub CLI](https://cli.github.com) (`gh`) and [Claude Code](https://claude.com/claude-code) (`claude`), both logged in.

1. In your repo, create `.github/workflows/pr.yml` and paste in the block below.
2. Get a Claude token and save it as a secret on the repo. Replace `<owner>/<repo>` with your repo. Paste the token when `gh` asks for it:
   ```sh
   claude setup-token
   gh secret set CLAUDE_CODE_OAUTH_TOKEN -R <owner>/<repo>
   ```
3. Commit, push and open a PR. The checks appear at the bottom of the PR, and the review agents post one comment.

```yaml
name: pr

on:
  pull_request:
    # ready_for_review: the Claude review skips drafts, so run it when one is marked ready.
    types: [opened, synchronize, reopened, ready_for_review]

concurrency:
  group: pr-${{ github.event.pull_request.number }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  checks:
    uses: algrifff/argus/.github/workflows/node-checks.yml@v1

  security:
    uses: algrifff/argus/.github/workflows/security.yml@v1

  review:
    uses: algrifff/argus/.github/workflows/agent-review.yml@v1
    permissions:
      contents: read
      pull-requests: write
    with:
      agents: security,adversarial,standards
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

Delete any job you don't want. `checks` is for Node projects: it runs your `package.json` scripts.

Optionally add a `REVIEW.md` to the repo with its own rules. The agents read it, along with `CLAUDE.md` and `AGENTS.md`, and follow it over their general briefs.

### About the Claude token

- Each repo uses its own token, so reviews count against that repo owner's Claude plan. Without a token the review skips with a warning.
- GitHub only gives a repo's secrets to workflows running in that repo, so other repos using Argus can't see your token.
- Anyone with write access to your repo can use the token. PRs from forks don't get it, so the review skips on those.
- Argus code runs with your token whenever `v1` moves. Review changes from other contributors before you release them.

## Status and next steps

**Read this first if you're picking up the work.** Update it when you finish something.

Done:

- `checks` and `security` run green on real PRs.
- Argus is public, so callers fetch the briefs without an extra token.
- The review agents have run on a real PR. Each used the right model and effort, took 5 to 6 turns, and together they cost about $0.60 at API prices. They found two fair low-severity issues.
- Bun repos (`bun.lock` or `bun.lockb`) work in all three workflows.
- Reviews post one combined, terse comment instead of one per agent, with no inline comments. They can post as your own GitHub App for a custom name and avatar.

Not done yet, in order:

1. **Watch reviews on a PR with real code changes.** So far they've only reviewed a config-and-docs PR. Check:
   - The single Argus comment is edited, not duplicated, on the next push, and stays short.
   - The adversarial agent writes and runs tests under `argus-scratch/` when it suspects a bug.
   - Usage on your Claude plan stays reasonable for bigger diffs.
2. **Tune the briefs** from what the reviews get wrong: too noisy, missing things, or too costly.

Ideas for later: checks for other stacks (for example a `python-checks.yml`), an option for high-severity findings to fail the PR, and uploading the adversarial agent's tests as a build artifact.

## The checks

### `node-checks.yml`

Runs the repo's own `package.json` scripts, one check per script. Scripts the repo doesn't define are skipped, so each repo picks its own tools. It detects bun, pnpm, yarn or npm from the lockfile.

| Input | Default | What it is |
| --- | --- | --- |
| `scripts` | `["typecheck", "lint", "test", "build"]` | JSON list of scripts to run |
| `node-version` | `24` | |
| `working-directory` | `.` | For repos where `package.json` isn't at the root |
| `bun-version` | `latest` | For Bun repos. `security.yml` and `agent-review.yml` take it too |

### `security.yml`

| Check | What it does |
| --- | --- |
| `secrets (gitleaks)` | Scans the PR's commits for leaked keys and tokens |
| `code patterns (semgrep)` | Semgrep rules, `p/default` unless the `semgrep-config` input says otherwise. On a PR it fails only on findings the PR adds; findings already on the base branch don't count |
| `dependencies (audit)` | `bun audit`, `pnpm audit` or `npm audit`. Fails at the `audit-level` input (default `high`). `bun audit` can't skip dev dependencies, so they count too |

### `agent-review.yml`

Runs one Claude review per agent in parallel, then posts all their reports as one short PR comment, edited on each push. It's advisory: it never fails the PR because of what it finds. It skips draft PRs.

| Input | Default | What it is |
| --- | --- | --- |
| `agents` | `security,adversarial,standards` | Which briefs in `review-agents/` to run |
| `model` | (each brief's own) | Override the model for every agent, for example to try a cheaper one |
| `effort` | (each brief's own) | Override the effort for every agent |
| `extra-allowed-tools` | | More Claude Code tool rules, for example `Bash(cargo test:*)` |
| `app-client-id` | | Post the comment as this GitHub App instead of `github-actions`. See [Post as "Argus"](#post-as-argus-with-your-own-avatar) |
| `argus-repository`, `argus-ref` | `algrifff/argus`, `v1` | Where to fetch the briefs. Keep `argus-ref` in step with the `@v1` in your `uses:` line |

| Secret | |
| --- | --- |
| `CLAUDE_CODE_OAUTH_TOKEN` | From `claude setup-token`. Uses your Claude subscription. Or set `ANTHROPIC_API_KEY` to pay per token |
| `ARGUS_APP_PRIVATE_KEY` | Only with `app-client-id`. The app's private key |

### Post as "Argus" with your own avatar

By default the comment comes from `github-actions`. To give it your own name and picture, create a GitHub App once and post as it. One app works for all your repos.

1. **Create the app.** This link fills in the form: <https://github.com/settings/apps/new?description=Claude%20PR%20reviews&url=https://github.com/algrifff/argus&public=false&webhook_active=false&pull_requests=write>
   - **GitHub App name:** the name shown on comments, as `<name> [bot]`. Names are unique across GitHub, so pick another if it's taken.
   - Check that **Webhook → Active** is off and **Repository permissions → Pull requests** is **Read and write**. Leave the rest at No access.
   - Click **Create GitHub App**.
2. **Set the avatar.** On the app's **General** page, upload a square image under **Display information**.
3. **Get the ID and key.** In the app's left sidebar, open **Credentials**. Copy the **Client ID** (it starts with `Iv23`). Under **Key pairs**, click **New key**, and a `.pem` file downloads.
4. **Install it.** In the left sidebar, click **Install App**, choose **Only select repositories**, and pick each repo that runs the review.
5. **Give each repo the ID and key.** Replace `<owner>/<repo>` and the file name:
   ```sh
   # bash, zsh or Git Bash
   gh secret set ARGUS_APP_PRIVATE_KEY -R <owner>/<repo> < ~/Downloads/<app>.<date>.private-key.pem
   ```
   ```powershell
   # PowerShell
   Get-Content -Raw "$env:USERPROFILE\Downloads\<app>.<date>.private-key.pem" | gh secret set ARGUS_APP_PRIVATE_KEY -R <owner>/<repo>
   ```
   ```sh
   gh variable set ARGUS_APP_CLIENT_ID -R <owner>/<repo> -b <client-id>
   ```
   Then put the `.pem` in your password manager or delete it. You can make a new key at any time.
6. **Use it in `pr.yml`.** In the `review` job:
   ```yaml
       with:
         agents: security,adversarial,standards
         app-client-id: ${{ vars.ARGUS_APP_CLIENT_ID }}
       secrets:
         CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
         ARGUS_APP_PRIVATE_KEY: ${{ secrets.ARGUS_APP_PRIVATE_KEY }}
   ```

If the "Create GitHub App Token" step fails, the app usually isn't installed on that repo, the ID and key are from different apps, or the app can't write to pull requests.

## The agents

Each brief in `review-agents/` is one agent. Its frontmatter sets the model and effort, chosen to keep usage down:

| Agent | Model | Effort | Turn limit | Job |
| --- | --- | --- | --- | --- |
| `security` | Opus 5.5 | high | 30 | Injection, leaked secrets, unsafe handling of model output, CI risks |
| `adversarial` | Opus 5.5 | medium | 40 | Tries to break the code and proves bugs with failing tests |
| `standards` | Sonnet 5.5 | medium | 20 | Checks the PR fits the repo's rules and patterns |

`_shared.md` is added to every agent's prompt. It holds the rules they all follow and the report format: `No issues.`, or one line per finding with file, line, failure and fix.

### Add an agent

1. Create `review-agents/<name>.md`:
   ```markdown
   ---
   model: claude-sonnet-5-5
   effort: medium
   max-turns: 20
   ---

   # <Name> reviewer

   What to look for, and what counts as high, medium or low severity.
   ```
2. Open a PR. CI checks the frontmatter (`scripts/check-briefs.sh`).
3. After it merges, [release](#releasing) and add the name to a repo's `agents:` list.

## Releasing

Repos pin `@v1`. `v1` is a tag that moves to the latest compatible release, so a repo gets fixes without editing its workflow. To release, merge to `main` and then run:

```sh
git tag -f v1 && git push -f origin v1
```

For a change that breaks callers, such as a renamed or removed input or a changed secret, tag `v2` instead. Update the callers' `uses:` and `argus-ref` lines yourself.

## Repo layout

```
.github/workflows/
  node-checks.yml   # shared: package.json scripts
  security.yml      # shared: gitleaks, Semgrep, audit
  agent-review.yml  # shared: Claude review agents
  ci.yml            # Argus's own checks: actionlint, brief frontmatter, security
review-agents/      # one brief per agent, plus _shared.md
scripts/check-briefs.sh
```

Every action is pinned to a commit SHA. Dependabot keeps the pins current.

## Why "Argus"

Named after Argus Panoptes, the giant with a hundred eyes who never slept on watch.
