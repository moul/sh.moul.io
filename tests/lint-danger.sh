#!/bin/sh
# lint-danger.sh: the patterns that turn a convenience script into an incident.
#
# Every rule here is one this repo broke at some point, or came close to. A linter that
# repeats generic advice gets ignored; these are specific, and each has a story.
#
# This file is excluded from its own scan: it holds the patterns it looks for.
set -eu
cd "$(dirname "$0")/.."

FAIL=0
ok()  { printf ' ok  %s\n' "$*"; }
bad() { printf 'fail %s\n' "$*" >&2; FAIL=1; }

SCRIPTS="$(find . -name '*.sh' -not -path './public/*' -not -path './.git/*' \
           -not -name 'lint-danger.sh' | sort | tr '\n' ' ')"

# Code only: comments and here-documents carry the published one-liners on purpose.
# shellcheck disable=SC2086  # SCRIPTS is a list of files and must split into arguments
hits() { grep -nHE "$1" $SCRIPTS 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#' || true; }

check() { # check <description> <regex that must not appear> [regex that is allowed anyway]
  if [ $# -gt 2 ]; then
    found="$(hits "$2" | grep -vE "$3" || true)"
  else
    found="$(hits "$2")"
  fi
  if [ -n "$found" ]; then
    bad "$1"
    printf '     %s\n' "$found" | head -3 >&2
  else
    ok "$1"
  fi
}

# We tell people to read a script before piping it into a shell. Doing the opposite inside
# our own would be telling them to do as we say and not as we do.
check "no URL piped straight into a shell" '^[[:space:]]*curl[^#]*\|[[:space:]]*(sh|bash)'
# A predictable name in a shared temp directory is somebody else's symlink, and the gap
# between writing a file and running it is the window they need.
check "no fixed paths under a shared temp directory" '(^|[^A-Za-z0-9_"])/tmp/[A-Za-z0-9._-]+'
# Loopback is the exception: the serve test has to fetch from its own http server.
check "no plain http downloads" 'curl[^|]*http://' 'http://(127\.0\.0\.1|localhost)' 
check "no eval" '(^|[^A-Za-z0-9_])eval[[:space:]]'
check "no world writable modes" 'chmod[[:space:]]+(-R[[:space:]]+)?[0-7]*77[0-7]?([[:space:]]|$)'
# rm -rf on a variable that can be empty is how home directories disappear.
check "no rm -rf on a bare variable" 'rm[[:space:]]+-[a-z]*r[a-z]*f?[[:space:]]+\$[A-Za-z_{]'
check "no double brackets" '\[\[[[:space:]]'
check "no local keyword" '(^|[[:space:]])local[[:space:]]'
check "no echo flags" 'echo[[:space:]]+-[en][[:space:]]'
check "no here strings" '<<<'

# Pin https at the protocol level, not just in the URL text: without it a redirect to
# http is followed silently.
for f in index.sh agents.sh; do
  if grep -qE '^[[:space:]]*[^#]*curl ' "$f" && ! grep -qE "curl[^|]*--proto '=https'" "$f"; then
    bad "$f downloads without pinning https"
  fi
done
ok "downloads pin https"

for f in $SCRIPTS; do
  [ -x "$f" ] || bad "not executable: $f"
  grep -qE '^set -' "$f" || bad "$f sets no shell options"
done
ok "exec bits and shell options"

# The published scripts are piped into whatever /bin/sh happens to be on the machine.
for f in index.sh agents.sh; do
  head -1 "$f" | grep -qx '#!/bin/sh' || bad "$f must declare #!/bin/sh: it is piped into sh"
done
ok "served scripts declare POSIX sh"

# A script that hangs on a dead endpoint is worse than one that fails: bound every fetch.
# Continuation lines are joined first, or a flag on one line and the URL on the next reads
# as two separate things. A real fetch writes to a file or is captured, which is what
# separates it from the usage examples in the help text.
for f in index.sh agents.sh; do
  flagged="$(sed -e :a -e '/\\$/N; s/\\\n//; ta' "$f" \
    | grep -vE '^[[:space:]]*#' \
    | grep -E 'curl ' | grep -E '(-o |\$\()' \
    | grep -vE '(--max-time|--connect-timeout)' || true)"
  if [ -n "$flagged" ]; then
    bad "$f has a fetch with no timeout"
    printf '     %s\n' "$flagged" | head -2 >&2
  fi
done
ok "fetches are bounded"

# Formatting rules that exist because these files are read in a browser before being piped
# into a shell. A formatter was considered and rejected: the ones available expand compact
# one-line guards into four lines each, which makes a script people have to read longer
# without making it clearer. These are the invariants that actually matter.
for f in $SCRIPTS; do
  printf '%s' "$(tail -c 1 "$f")" | grep -q . && bad "$f does not end with a newline"
  grep -qP '\t' "$f" 2>/dev/null && bad "$f contains tabs"
  grep -qE ' +$' "$f" && bad "$f has trailing whitespace"
  # The box drawing character in section headers is three bytes, and awk counts bytes on
  # some systems and characters on others. Strip it first, or this rule passes on one
  # machine and fails on the next for no reason anybody can see.
  long="$(awk '{ l = $0; gsub(/─/, "", l); if (length(l) > 120) print FILENAME ":" NR }' "$f" | head -1)"
  [ -n "$long" ] && bad "line over 120 characters: $long"
done
ok "formatting: no tabs, no trailing whitespace, nothing over 120 columns"

echo
[ "$FAIL" = 0 ] || { echo 'lint-danger: FAILED' >&2; exit 1; }
echo 'lint-danger: clean'
