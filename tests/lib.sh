# Sourced by the tests: pulls one step's `run` out of a workflow, reports results and makes fixture
# repositories.

# step <workflow.yml> <job> <step id>: prints that step's script.
step() {
  "${PYTHON:-python3}" -c '
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"][sys.argv[2]]["steps"]
print(next(s["run"] for s in steps if s.get("id") == sys.argv[3]))
' "$@"
}

fail=0
# check <description> <want> <got>
check() {
  if [ "$2" = "$3" ]; then echo "ok   $1"
  else printf 'FAIL %s\n     want: %s\n     got:  %s\n' "$1" "$2" "$3"; fail=1; fi
}

# A scratch repository for fixtures; the global hooks do not apply to it.
scratch_repo() {
  git init -q -b main "$1"
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name t
  git -C "$1" config core.hooksPath /dev/null
}
