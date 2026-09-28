#!/bin/sh
# The whole test suite: syntax, lint, help and implementation agreeing, and every
# subcommand surviving a dry run. No network, no installs, nothing written outside a
# throwaway HOME.
set -eu
cd "$(dirname "$0")/.."

FAIL=0
ok()  { printf ' ok  %s\n' "$*"; }
bad() { printf 'fail %s\n' "$*" >&2; FAIL=1; }

for f in index.sh agents.sh bin/build.sh tests/test.sh; do
  sh -n "$f" || bad "sh -n: $f"
  [ -x "$f" ] || bad "not executable: $f"
done
ok "syntax and exec bits"

if command -v shellcheck >/dev/null; then
  shellcheck -s sh -S warning index.sh agents.sh bin/build.sh tests/test.sh \
    && ok "shellcheck" || bad "shellcheck"
else
  printf 'warn %s\n' "shellcheck absent, skipped" >&2
fi

# Help is generated from a table, so the table and the functions must agree both ways.
# This is the check that stops a subcommand existing without being documented, and the
# reverse: a help entry for something that was deleted years ago.
listed="$(grep -oE '^[a-z_]+\|' index.sh | tr -d '|' | sort)"
defined="$(grep -oE '^sub_[a-z_]+\(\)' index.sh | sed 's/^sub_//;s/()//' | grep -v '^help$' | sort)"
if [ "$listed" = "$defined" ]; then
  ok "help and implementation agree ($(echo "$listed" | grep -c .) subcommands)"
else
  bad "help and implementation disagree"
  printf '     listed in help: %s\n' "$(echo "$listed" | tr '\n' ' ')" >&2
  printf '     defined below:  %s\n' "$(echo "$defined" | tr '\n' ' ')" >&2
fi

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin"
printf '#!/bin/sh\necho "tests must not call sudo" >&2\nexit 7\n' >"$SANDBOX/bin/sudo"
chmod +x "$SANDBOX/bin/sudo"

for sub in $defined; do
  out="$(HOME="$SANDBOX" PATH="$SANDBOX/bin:$PATH" DRY=1 sh index.sh "$sub" 2>&1)" || {
    bad "dry run failed: $sub"; printf '%s\n' "$out" >&2; continue; }
  # The stub speaks up if it is ever actually called. A printed "dry  sudo ..." line is
  # the correct behaviour and must not trip this.
  case "$out" in *"tests must not call sudo"*) bad "$sub called sudo during a dry run" ;; esac
done
ok "every subcommand survives a dry run"

[ -e "$SANDBOX/.ssh" ] && bad "a dry run wrote into the sandbox home" || ok "dry runs wrote nothing"

sh index.sh | grep -q 'Subcommands:' && ok "no arguments prints the help" || bad "help is missing"
if sh index.sh definitely_not_a_subcommand >/dev/null 2>&1; then
  bad "an unknown subcommand exited 0"
else
  ok "an unknown subcommand fails"
fi

./bin/build.sh >/dev/null && [ -f public/agents ] && [ -f public/index.html ] \
  && ok "the build produces the published paths" || bad "build"
grep -q 'VERSION="dev"' public/index.html && bad "the build did not stamp the version" \
  || ok "the build stamps the commit"

echo
[ "$FAIL" = 0 ] || { echo 'tests: FAILED' >&2; exit 1; }
echo 'tests: clean'
