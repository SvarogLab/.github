# Sourced by the tests: reports results and makes fixture repositories.

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
