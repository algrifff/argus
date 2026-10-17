# Argus

Shared pull request checks for all my repos: tests, lint, security scans, and Claude agents that review each PR. A repo adds one small workflow file and picks the checks and agents it needs.

Named after Argus Panoptes, the giant with a hundred eyes who never slept on watch.

## Status and next steps

**Read this first if you're picking up the work.** Update it when you finish something.

Done:

- The checks were built and tested inside [tripous](https://github.com/algrifff/tripous) (PRs #2 and #4), then moved here.
- `checks` and `security` run green on real PRs.
- tripous calls Argus at `@v1` ([tripous#6](https://github.com/algrifff/tripous/pull/6)).
- Argus is public, so callers fetch the briefs without an extra token.
- tripous has its `CLAUDE_CODE_OAUTH_TOKEN` secret set.
- The review agents ran for real on [tripous#6](https://github.com/algrifff/tripous/pull/6). Each posted one comment with the right model and effort. Together they took 5 to 6 turns each and about $0.60 at API prices, and found two fair low-severity issues.
- Bun repos (`bun.lock` or `bun.lockb`) work in all three workflows. dnd-sync is the first Bun caller.

Not done yet, in order:

1. **Watch reviews on a PR with real code changes.** So far they've only reviewed a config-and-docs PR, and none left an inline comment. Check:
   - The comment is edited, not duplicated, on the next push.
   - Inline comments land on the right lines.
   - The adversarial agent writes and runs tests under `argus-scratch/` when it suspects a bug.
   - Usage on your Claude plan stays reasonable for bigger diffs.
2. **Tune the briefs** from what the reviews get wrong: too noisy, missing things, or too costly.

Ideas for later: checks for other stacks (for example a `python-checks.yml`), an option for high-severity findings to fail the PR, and uploading the adversarial agent's tests as a build artifact.

## Use it in a repo

Add `.github/workflows/pr.yml`:

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

Leave out any job the repo doesn't need. Then:

- Set the Claude token on the repo: run `claude setup-token`, then `gh secret set CLAUDE_CODE_OAUTH_TOKEN -R <owner>/<repo>` and paste the token. Each repo uses its own token, so reviews count against that owner's plan. Without a token the review skips with a warning.
  - GitHub only gives a repo's secrets to workflows running in that repo, so other repos using Argus can't see your token.
  - Anyone with write access to your repo can use the token. PRs from forks don't get it, so the review skips on those.
  - Argus code runs with your token whenever `v1` moves. Review changes from other contributors before you release them.
- Optionally add a `REVIEW.md` to the repo with its own rules. The agents read it, along with `CLAUDE.md` and `AGENTS.md`, and follow it over their general briefs.

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

Runs one Claude review per agent and posts one PR comment per agent, edited on each push. It's advisory: it never fails the PR because of what it finds. It skips draft PRs.

| Input | Default | What it is |
| --- | --- | --- |
| `agents` | `security,adversarial,standards` | Which briefs in `review-agents/` to run |
| `model` | (each brief's own) | Override the model for every agent, for example to try a cheaper one |
| `effort` | (each brief's own) | Override the effort for every agent |
| `extra-allowed-tools` | | More Claude Code tool rules, for example `Bash(cargo test:*)` |
| `argus-repository`, `argus-ref` | `algrifff/argus`, `v1` | Where to fetch the briefs. Keep `argus-ref` in step with the `@v1` in your `uses:` line |

| Secret | |
| --- | --- |
| `CLAUDE_CODE_OAUTH_TOKEN` | From `claude setup-token`. Uses your Claude subscription. Or set `ANTHROPIC_API_KEY` to pay per token |

## The agents

Each brief in `review-agents/` is one agent. Its frontmatter sets the model and effort, chosen to keep usage down:

| Agent | Model | Effort | Turn limit | Job |
| --- | --- | --- | --- | --- |
| `security` | Opus 5.5 | high | 30 | Injection, leaked secrets, unsafe handling of model output, CI risks |
| `adversarial` | Opus 5.5 | medium | 40 | Tries to break the code and proves bugs with failing tests |
| `standards` | Sonnet 5.5 | medium | 20 | Checks the PR fits the repo's rules and patterns |

`_shared.md` is added to every agent's prompt. It holds the rules they all follow and the report format.

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
