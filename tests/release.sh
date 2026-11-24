#!/usr/bin/env bash
# release.yml's create step with gh and git-cliff replaced on PATH: the assets are what it attaches, and
# a downloaded chart goes with them.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
script=$(step "$(pwd)/.github/workflows/release.yml" github-release create) || { echo "FAIL: no step create"; exit 1; }

work=$(mktemp -d); bin=$work/bin; mkdir "$bin"
printf '#!/usr/bin/env bash\necho notes\n' > "$bin/git-cliff"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$GH_LOG"\n' > "$bin/gh"
chmod +x "$bin/gh" "$bin/git-cliff"

# attached <dir> <download-chart>: the files gh was asked to attach, sorted, or "step failed".
attached() {
  (cd "$1" && env PATH="$bin:$PATH" GH_LOG="$work/gh.log" RUNNER_TEMP="$work" RELEASE_TAG=v1.2.3 \
    ASSETS="app-linux-amd64" LATEST=true DOWNLOAD_CHART="$2" bash -euo pipefail -c "$script" >/dev/null 2>&1) ||
    { echo "step failed"; return; }
  sed -n '4,/^--title$/p' "$work/gh.log" | grep -v '^--title$' | LC_ALL=C sort | paste -sd' '
}

mkdir -p "$work/plain" "$work/chart/chart"
check "the assets are attached" "app-linux-amd64" "$(attached "$work/plain" false)"
: > "$work/chart/chart/demo-1.2.3.tgz"
check "the downloaded chart goes with them" "app-linux-amd64 chart/demo-1.2.3.tgz" "$(attached "$work/chart" true)"
check "a chart asked for and missing fails" "step failed" "$(attached "$work/plain" true)"

exit $fail
