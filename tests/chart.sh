#!/usr/bin/env bash
# chart.yml's package step with a real helm: the chart takes the tag's version, bare, and deploys the
# image the tag names by default.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
package=$(step "$(pwd)/.github/workflows/chart.yml" chart package) || { echo "FAIL: no step package"; exit 1; }

work=$(mktemp -d)
mkdir -p "$work/helm/templates"
printf 'apiVersion: v2\nname: demo\nversion: 0.0.0\n' > "$work/helm/Chart.yaml"

(cd "$work" && env TAG=v1.2.3 CHART=helm RUNNER_TEMP="$work" bash -euo pipefail -c "$package" >/dev/null 2>&1)
check "packaged at the tag's version" "demo-1.2.3.tgz" "$(ls "$work/chart" 2>/dev/null)"
check "the chart version is bare, appVersion the image tag" "1.2.3 v1.2.3" \
  "$(tar -xzOf "$work/chart/demo-1.2.3.tgz" demo/Chart.yaml 2>/dev/null | "${PYTHON:-python3}" -c '
import sys, yaml
c = yaml.safe_load(sys.stdin)
print(c["version"], c["appVersion"])')"

exit $fail
