#!/usr/bin/env bash
# The preset updates the way README.md says: Renovate runs in dry-run on fixture repositories with default.json
# from this tree, and the requirement it would write is compared with the expected one.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
preset=$(realpath "$(dirname "$0")/../default.json")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# run_renovate <fixture dir>: Renovate's debug log for the fixture, in $tmp/renovate.log. A Renovate that does
# not run fails here with its log.
run_renovate() {
  if ! (cd "$1" && LOG_LEVEL=debug LOG_FORMAT=json RENOVATE_CONFIG_FILE="$tmp/config.json" \
    RENOVATE_GITHUB_COM_TOKEN="${GITHUB_COM_TOKEN:-${GITHUB_TOKEN:-}}" \
    npx --yes renovate@44 --platform=local --dry-run=lookup >"$tmp/renovate.log" 2>&1); then
    echo "renovate did not run:" >&2
    tail -n 20 "$tmp/renovate.log" >&2
    return 1
  fi
}

# requirement <fixture dir> <dep>: "<current> -> <new>" for the dependency's first update, "<current> -> <current>"
# when Renovate offers none. A dependency Renovate did not look up - its github.com lookups go unanswered without
# a token - fails here with the log's warnings rather than reading as one left alone.
requirement() {
  run_renovate "$1" || return 1
  local found
  found=$(jq -rR --arg dep "$2" 'fromjson? | select(.msg? == "packageFiles with updates")
    | .config.cargo[].deps[] | select(.depName == $dep)
    | "\(.currentValue) -> \(.updates[0].newValue // .currentValue)"' "$tmp/renovate.log")
  if [ -z "$found" ]; then
    echo "renovate looked up no $2:" >&2
    jq -rR 'fromjson? | select(.level >= 40) | .msg' "$tmp/renovate.log" | tail -n 20 >&2
    return 1
  fi
  echo "$found"
}

# branches <fixture dir>: the branch names Renovate would create there, sorted, on one line.
branches() {
  run_renovate "$1" || return 1
  jq -rR 'fromjson? | select(.branch?) | .branch' "$tmp/renovate.log" | sort -u | paste -sd' '
}

"${PYTHON:-python3}" - "$preset" "$tmp/config.json" <<'PY'
import json, sys
preset = json.load(open(sys.argv[1]))
preset.pop("$schema", None)
preset["onboarding"] = False
preset["requireConfig"] = "ignored"
json.dump(preset, open(sys.argv[2], "w"))
PY

# fixture <dir> [lock]: a crate requiring serde_json 1.0.100, with a Cargo.lock that resolves it when asked.
fixture() {
  scratch_repo "$1"
  cat >"$1/Cargo.toml" <<'TOML'
[package]
name = "fixture"
version = "0.1.0"
edition = "2024"

[dependencies]
serde_json = "1.0.100"
TOML
  if [ "${2:-}" = lock ]; then
    cat >"$1/Cargo.lock" <<'LOCK'
version = 4

[[package]]
name = "fixture"
version = "0.1.0"
dependencies = ["serde_json"]

[[package]]
name = "serde_json"
version = "1.0.100"
source = "registry+https://github.com/rust-lang/crates.io-index"
LOCK
  fi
  git -C "$1" add . && git -C "$1" commit -qm fixture
}

# Without a lock file there is nothing else to move: a release inside the range reaches no build until the
# requirement names it.
fixture "$tmp/unlocked"
got=$(requirement "$tmp/unlocked" serde_json) || { echo "FAIL lock-file-less requirement is raised: no result"; exit 1; }
check "lock-file-less requirement is raised" "raised" "$([ "${got%% -> *}" != "${got##* -> }" ] && echo raised || echo "kept: $got")"

# With one, the requirement still follows what the lock file resolves.
fixture "$tmp/locked" lock
got=$(requirement "$tmp/locked" serde_json) || { echo "FAIL locked requirement is raised: no result"; exit 1; }
check "locked requirement is raised" "raised" "$([ "${got%% -> *}" != "${got##* -> }" ] && echo raised || echo "kept: $got")"

# kube pins the k8s-openapi minor it builds against. A kube major needs a k8s-openapi minor; in two branches,
# neither builds alone.
scratch_repo "$tmp/kube"
cat >"$tmp/kube/Cargo.toml" <<'TOML'
[package]
name = "fixture"
version = "0.1.0"
edition = "2024"

[dependencies]
kube = "4.2.0"
k8s-openapi = "0.28.0"
TOML
git -C "$tmp/kube" add . && git -C "$tmp/kube" commit -qm fixture
got=$(branches "$tmp/kube") || { echo "FAIL kube and k8s-openapi share one branch: no result"; exit 1; }
check "kube and k8s-openapi share one branch" "renovate/kube" "$got"

# Compatible updates share one branch, so they cannot conflict with each other on neighbouring Cargo.toml
# lines; a 0.x minor breaks the API and keeps a branch of its own.
scratch_repo "$tmp/nonmajor"
cat >"$tmp/nonmajor/Cargo.toml" <<'TOML'
[package]
name = "fixture"
version = "0.1.0"
edition = "2024"

[dependencies]
serde_json = "1.0.100"
tokio = "1.40.0"
hex = "0.4.0"
base64 = "0.21.0"
TOML
git -C "$tmp/nonmajor" add . && git -C "$tmp/nonmajor" commit -qm fixture
got=$(branches "$tmp/nonmajor") || { echo "FAIL compatible updates share one branch: no result"; exit 1; }
check "compatible updates share one branch" "renovate/base64-0.x renovate/non-major" "$got"

exit $fail
