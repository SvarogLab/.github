# .github

Shared configuration for SvarogLab repositories.

## Renovate preset

[`default.json`](default.json) is the Renovate preset these repositories share. Renovate runs self-hosted, hourly
from 08:00 to 18:00 UTC, and only on a repository that carries its own configuration: one without is skipped, and
no onboarding pull request is ever opened. It opens pull requests and never merges them.

A repository opts in with a `renovate.json` at its root:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>SvarogLab/.github"]
}
```

What the preset sets on top of `config:recommended`:

- **Conventional commit subjects.** `semanticCommits` is forced on rather than guessed from history, so every
  update is `fix(deps): ...` for a runtime dependency and `chore(deps): ...` for the rest, and `git-cliff` files
  it correctly in the changelog.
- **No dependency dashboard issue.** Open pull requests are the list of what is pending.
- **No pull request caps.** Each run opens one for every update published since the last, instead of spreading
  them over later runs.
- **Weekly lock file maintenance**, during Monday's runs. Updates to direct dependencies only move what they
  need; this refreshes the transitive ones in `Cargo.lock` and its peers. Renovate's default for it is before
  04:00, when no run happens, so the schedule is set here.

A repository changes any of this for itself by adding keys next to `extends` in its own `renovate.json`.
