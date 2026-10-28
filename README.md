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
- **Rebased whenever `main` moves.** A pull request's checks ran against the `main` it was opened on; merging
  another one first leaves that combination untested. `rebaseWhen: behind-base-branch` has the next run rebase
  every pull request that has fallen behind, so its checks run again on top of what was merged.

These repositories do not commit `Cargo.lock`: every build resolves dependencies afresh and so takes any release
a `Cargo.toml` range allows. Renovate therefore opens a pull request only for a release outside the range - a new
major version, or a new minor one below 1.0 - and has no lock file to maintain.

A repository changes any of this for itself by adding keys next to `extends` in its own `renovate.json`.

## Shared workflows

Reusable workflows under [`.github/workflows/`](.github/workflows/), called by a version tag:
`uses: SvarogLab/.github/.github/workflows/<name>.yml@v1`. A ruleset makes `v*` tags immutable - they can be
neither moved nor deleted - so a caller always runs exactly the workflows it was last checked against. A change
here ships as a new tag (`v1.1`, then `v1.2`, ...), and each repository moves to it in a pull request of its own.

- [`rust.yml`](.github/workflows/rust.yml) - `cargo fmt`, `cargo audit`, and per arch on its own runner
  clippy, tests and the release build: Linux on the musl target for amd64 and arm64, and, when `windows-args` is
  set, Windows on the MSVC target for amd64 and arm64. Code behind `cfg(windows)` compiles to nothing on Linux,
  so a Windows part of a workspace is checked only by the Windows job. `binaries` and `windows-binaries` name the
  binaries each release build uploads as `binaries-*` artifacts. A crate linking a system library that musl has
  no build of, such as pcsc-lite, sets `linux-libc: gnu` and names the `-dev` package in `apt-packages`.
- [`release-pr.yml`](.github/workflows/release-pr.yml) - opens the release pull request: the next version
  `git-cliff` computes from the commits since the last tag, the version files moved to it by the caller's `bump`
  shell, and `CHANGELOG.md` regenerated. The pull request is opened with `GITHUB_TOKEN`, so no workflow runs on it;
  its only changes are the version and the changelog.
- [`tag-release.yml`](.github/workflows/tag-release.yml) - tags the merged `chore: release vX.Y.Z` commit on
  `main`. A tag pushed with `GITHUB_TOKEN` starts no workflow, so the caller releases in the same run.
- [`release.yml`](.github/workflows/release.yml) - creates the GitHub Release for the tag, with the binaries
  `rust.yml` built in the same run and the tag's `CHANGELOG.md` section as its notes.

A repository releasing its binaries wires them together like this; `release-pr.yml` is started by hand from
the Actions tab:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: ["**"]
  pull_request:
  schedule:
    - cron: "0 6 * * *"

permissions:
  contents: read

jobs:
  rust:
    uses: SvarogLab/.github/.github/workflows/rust.yml@v1
    with:
      binaries: example

  tag:
    needs: rust
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    uses: SvarogLab/.github/.github/workflows/tag-release.yml@v1
    permissions:
      contents: write

  release:
    needs: tag
    if: needs.tag.outputs.tag != ''
    uses: SvarogLab/.github/.github/workflows/release.yml@v1
    permissions:
      contents: write
    with:
      tag: ${{ needs.tag.outputs.tag }}
      download-binaries: true
      prepare: cp binaries/amd64/release/example example-linux-amd64
      assets: example-linux-amd64
```

```yaml
# .github/workflows/release-pr.yml
name: Release PR

on:
  workflow_dispatch:
    inputs:
      version:
        description: Version to release; empty computes it from the commits since the last tag.
        required: false

permissions:
  contents: read

jobs:
  release-pr:
    uses: SvarogLab/.github/.github/workflows/release-pr.yml@v1
    permissions:
      contents: write
      pull-requests: write
    with:
      version: ${{ inputs.version }}
      bump: sed -i "s/^version = \".*\"/version = \"$VERSION_NUMBER\"/" Cargo.toml
```

The daily `schedule` run matters because no repository here commits `Cargo.lock`: a release inside a
`Cargo.toml` range can break the build without any pull request, and only a run against `main` shows it.
