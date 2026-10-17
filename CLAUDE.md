# Argus

Shared, reusable GitHub Actions workflows and Claude review-agent briefs, called from other repos at `@v1`.

- Start with the README's **Status and next steps** section. It says what's done and what's next. Update it when you finish something.
- Shared workflows must stay in `.github/workflows/` (GitHub requires it). Briefs live in `review-agents/`.
- Pin every action to a full commit SHA with a `# vX.Y.Z` comment. Semgrep's security scan fails on tags.
- Changing an input, secret or output that callers use is a breaking change: release it as `v2`, not `v1`.
- tripous (`C:\Users\alexg\Desktop\tripous`, `algrifff/tripous`) is the first caller and the test bed.
