#!/usr/bin/env bash
# image.yml's steps. A release build makes the run's binaries executable again, builds the caller's
# Dockerfile for its arch and pushes it by digest; the merge tags the digests as one manifest. A pull
# request's check builds the same Dockerfile from placeholders, pushing nothing, and fails where the
# release would. The builds need docker buildx, the push a registry in TEST_REGISTRY.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
yml=$(pwd)/.github/workflows/image.yml
executable=$(step "$yml" build executable) || { echo "FAIL: no step executable"; exit 1; }
placeholders=$(step "$yml" build placeholders) || { echo "FAIL: no step placeholders"; exit 1; }
build=$(step "$yml" build build) || { echo "FAIL: no step build"; exit 1; }
digest=$(step "$yml" build digest) || { echo "FAIL: no step digest"; exit 1; }
manifest=$(step "$yml" merge manifest) || { echo "FAIL: no step manifest"; exit 1; }

case $(uname -m) in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac
work=$(mktemp -d)

# An artifact keeps no file modes: the downloaded binaries arrive as 0644.
mkdir -p "$work/modes/target/$arch/release"
: > "$work/modes/target/$arch/release/app"; chmod 0644 "$work/modes/target/$arch/release/app"
(cd "$work/modes" && env ARCH="$arch" bash -euo pipefail -c "$executable" >/dev/null 2>&1)
check "the downloaded binaries are executable" "755" "$(stat -c %a "$work/modes/target/$arch/release/app")"

(cd "$work/modes" && rm -rf target && env ARCH=amd64 BINARIES="a b" bash -euo pipefail -c "$placeholders" >/dev/null 2>&1)
check "a placeholder at every binary's path" "target/amd64/release/a target/amd64/release/b" \
  "$(cd "$work/modes" && find target -type f | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
check "a check without binaries named fails" "1" \
  "$(cd "$work/modes" && env ARCH=amd64 BINARIES="" bash -euo pipefail -c "$placeholders" >/dev/null 2>&1; echo $?)"

mkdir "$work/bin"
printf '#!/usr/bin/env bash\ntouch "$DOCKER_RAN"\n' > "$work/bin/docker"; chmod +x "$work/bin/docker"
(cd "$work/modes" && env ARCH="$arch" PUSH=true TAG="" REGISTRY=ghcr.io GITHUB_REPOSITORY=O/Demo RUNNER_TEMP="$work" \
  PATH="$work/bin:$PATH" DOCKER_RAN="$work/docker-ran" bash -euo pipefail -c "$build" >/dev/null 2>&1)
check "a push without a tag fails before building" "1 not built" \
  "$? $([ -e "$work/docker-ran" ] && echo built || echo "not built")"

docker buildx version >/dev/null 2>&1 || { echo "skip the builds: no docker buildx here"; exit $fail; }

# fixture <dir> <.dockerignore>: a caller whose Dockerfile copies `app`.
fixture() {
  mkdir -p "$1"
  printf 'FROM scratch\nARG TARGETARCH\nCOPY target/${TARGETARCH}/release/app /app\n' > "$1/Dockerfile"
  printf '%b' "$2" > "$1/.dockerignore"
  (cd "$1" && env ARCH="$arch" BINARIES=app bash -euo pipefail -c "$placeholders" >/dev/null 2>&1)
}

# build <repo dir> <push> [registry]: exit status of the build step, with its log on failure.
build() {
  (cd "$1" && env ARCH="$arch" PUSH="$2" TAG=v1.2.3 REGISTRY="${3:-ghcr.io}" GITHUB_REPOSITORY=O/Demo \
    RUNNER_TEMP="$work" bash -euo pipefail -c "$build" >"$work/log" 2>&1)
  local status=$?
  [ $status -eq 0 ] || tail -15 "$work/log" >&2
  echo $status
}

fixture "$work/check" '*\n!target/*/release/app\n'
check "a check builds from placeholders" "0" "$(build "$work/check" false)"
fixture "$work/broken" '*\n'
check "a check fails on a .dockerignore the release would fail on" "1" "$(build "$work/broken" false 2>/dev/null)"

# The release path against a registry the test runs: push by digest under the lowercased repository,
# export the digest the way the merge reads it, and tag the manifest.
if [ -n "${TEST_REGISTRY:-}" ]; then
  check "pushes by digest" "0" "$(build "$work/check" true "$TEST_REGISTRY")"
  (env RUNNER_TEMP="$work" bash -euo pipefail -c "$digest" >/dev/null 2>&1)
  check "exports the digest" "0" "$?"
  (cd "$work/digests" && env REGISTRY="$TEST_REGISTRY" GITHUB_REPOSITORY=O/Demo TAG=v1.2.3 \
    bash -euo pipefail -c "$manifest" >"$work/log" 2>&1) || tail -15 "$work/log" >&2
  check "the tag names a manifest for the built arch" "linux/$arch" \
    "$(docker buildx imagetools inspect "$TEST_REGISTRY/o/demo:v1.2.3" --raw 2>/dev/null |
      jq -r '.manifests[].platform | select(.os != "unknown") | "\(.os)/\(.architecture)"')"
else
  echo "skip the push: no TEST_REGISTRY"
fi
exit $fail
