#!/usr/bin/env bash
# The preset updates the way README.md says: Renovate runs in dry-run on fixture repositories with default.json
# from this tree, and the requirement it would write is compared with the expected one.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
preset=$(realpath "$(dirname "$0")/../default.json")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# requirement <fixture dir> <dep>: "<current> -> <new>" for the dependency's first update, "<current> -> <current>"
# when Renovate offers none. A Renovate that does not run or looks nothing up fails here with its log rather
# than reading as a dependency left alone.
requirement() {
  local log="$tmp/renovate.log"
  if ! (cd "$1" && LOG_LEVEL=debug LOG_FORMAT=json RENOVATE_CONFIG_FILE="$tmp/config.json" \
    RENOVATE_GITHUB_COM_TOKEN="${GITHUB_COM_TOKEN:-${GITHUB_TOKEN:-}}" \
    npx --yes renovate@44 --platform=local --dry-run=lookup >"$log" 2>&1); then
    echo "renovate did not run:" >&2
    tail -n 20 "$log" >&2
    return 1
  fi
  local found
  found=$(jq -rR --arg dep "$2" 'fromjson? | select(.msg? == "packageFiles with updates")
    | .config.cargo[].deps[] | select(.depName == $dep)
    | "\(.currentValue) -> \(.updates[0].newValue // .currentValue)"' "$log")
  if [ -z "$found" ]; then
    echo "renovate looked up no $2:" >&2
    jq -rR 'fromjson? | select(.level >= 40) | .msg' "$log" | tail -n 20 >&2
    return 1
  fi
  echo "$found"
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

exit $fail
