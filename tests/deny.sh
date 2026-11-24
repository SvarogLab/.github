#!/usr/bin/env bash
# The cargo deny step of rust.yml, against fixture crates: the caller's deny.toml decides, and a
# license it does not allow fails the step.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
script=$(step "$(pwd)/.github/workflows/rust.yml" deny deny) || { echo "FAIL: no step deny"; exit 1; }

work=$(mktemp -d)

# run <license>: a crate under <license>, with a deny.toml that allows MIT only; prints pass or fail.
run() {
  local dir=$work/$1
  mkdir -p "$dir/src"
  cat >"$dir/Cargo.toml" <<TOML
[package]
name = "fixture"
version = "0.1.0"
edition = "2024"
license = "$1"
TOML
  echo 'fn main() {}' >"$dir/src/main.rs"
  cat >"$dir/deny.toml" <<'TOML'
[licenses]
allow = ["MIT"]
TOML
  (cd "$dir" && cargo generate-lockfile -q && bash -euo pipefail -c "$script" >/dev/null 2>&1) && echo pass || echo fail
}

check "an allowed license passes" pass "$(run MIT)"
check "a license deny.toml does not allow fails" fail "$(run GPL-3.0-only)"

exit $fail
