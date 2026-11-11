#!/usr/bin/env bash
# The step of release-pr.yml that opens the release PR, against a bare origin, with gh, git-cliff and
# cargo replaced on PATH: the release commit carries Cargo.lock at the new version.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
script=$(step "$(pwd)/.github/workflows/release-pr.yml" release-pr open) || { echo "FAIL: no step open"; exit 1; }

work=$(mktemp -d); bin=$work/bin; mkdir "$bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/gh"
# git-cliff: --bumped-version prints v0.3.0, -o writes the changelog, anything else prints notes.
cat > "$bin/git-cliff" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" --bumped-version "*) echo v0.3.0 ;;
  *" -o "*) echo changelog > CHANGELOG.md ;;
  *) echo notes ;;
esac
SH
# cargo: `update --workspace` marks Cargo.lock and records that it ran.
cat > "$bin/cargo" <<'SH'
#!/usr/bin/env bash
echo "cargo $*" >> "$CARGO_LOG"
[ "$*" != "update --workspace" ] || echo "# workspace at $VERSION_NUMBER" >> Cargo.lock
SH
chmod +x "$bin/gh" "$bin/git-cliff" "$bin/cargo"

# run <name> [lock]: a repository at v0.2.0, with a Cargo.lock when asked, released by the step;
# prints the release branch's Cargo.lock, and the cargo calls go to $work/<name>.cargo.
run() {
  local origin=$work/$1.git seed=$work/$1 clone
  git init -q --bare -b main "$origin"
  scratch_repo "$seed"
  echo 0.2.0 > "$seed/VERSION"
  [ "${2:-}" != lock ] || echo "# workspace at 0.2.0" > "$seed/Cargo.lock"
  git -C "$seed" add . && git -C "$seed" commit -q -m "feat: one"
  git -C "$seed" remote add origin "$origin" && git -C "$seed" push -q origin main
  clone=$(mktemp -d)/repo
  git clone -q "$origin" "$clone" && git -C "$clone" config core.hooksPath /dev/null
  (cd "$clone" && env PATH="$bin:$PATH" CARGO_LOG="$work/$1.cargo" GITHUB_REF_NAME=main REQUESTED= \
    BUMP='echo "$VERSION_NUMBER" > VERSION' bash -euo pipefail -c "$script" >/dev/null 2>&1) || echo "step failed"
  git -C "$origin" show refs/heads/chore/release-v0.3.0:Cargo.lock 2>/dev/null | tail -1
}

check "Cargo.lock follows the release version" "# workspace at 0.3.0" "$(run locked lock)"
check "no Cargo.lock, no cargo" "" "$(run unlocked; cat "$work/unlocked.cargo" 2>/dev/null)"

exit $fail
