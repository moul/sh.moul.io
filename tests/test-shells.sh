#!/bin/sh
# test-shells.sh: these scripts are piped into whatever /bin/sh happens to be.
#
# On Debian that is dash, on Alpine it is busybox ash, on macOS it is bash 3.2 pretending,
# and some people have zsh or ksh there. A bashism that works on the machine where it was
# written and fails on a fresh server is the single most common way a script like this
# breaks, so run everything under every shell present.
set -eu
cd "$(dirname "$0")/.."

FAIL=0
ok()  { printf ' ok  %s\n' "$*"; }
bad() { printf 'fail %s\n' "$*" >&2; FAIL=1; }

SHELLS=""
for candidate in sh dash bash zsh ksh mksh yash; do
  command -v "$candidate" >/dev/null 2>&1 && SHELLS="$SHELLS $candidate"
done
command -v busybox >/dev/null 2>&1 && SHELLS="$SHELLS busybox-sh"
[ -n "$SHELLS" ] || { echo "no shells found, which cannot happen" >&2; exit 1; }

runner() { # runner <shell> <script> [args...]
  case "$1" in
    busybox-sh) shift; busybox sh "$@" ;;
    *)          s="$1"; shift; "$s" "$@" ;;
  esac
}

SUBS="$(grep -oE '^sub_[a-z_]+\(\)' index.sh | sed 's/^sub_//;s/()//' | grep -v '^help$')"

for s in $SHELLS; do
  SANDBOX="$(mktemp -d)"
  mkdir -p "$SANDBOX/bin"
  printf '#!/bin/sh\necho "REFUSED sudo" >&2\nexit 7\n' >"$SANDBOX/bin/sudo"
  chmod +x "$SANDBOX/bin/sudo"

  if ! out="$(runner "$s" index.sh 2>&1)"; then
    bad "$s: the help failed"; printf '%s\n' "$out" >&2; rm -rf "$SANDBOX"; continue
  fi
  case "$out" in *Subcommands:*) ;; *) bad "$s: the help printed nothing useful" ;; esac

  sub_fail=0
  for sub in $SUBS; do
    if ! out="$(HOME="$SANDBOX" PATH="$SANDBOX/bin:$PATH" DRY=1 runner "$s" index.sh "$sub" 2>&1)"; then
      bad "$s: dry run of $sub failed"; printf '%s\n' "$out" | head -3 >&2; sub_fail=1
    fi
    case "$out" in *"REFUSED sudo"*) bad "$s: $sub called sudo in a dry run"; sub_fail=1 ;; esac
  done

  # The bootstrap itself, with the network part off and a key it can authorize offline.
  # It exits non-zero when the machine cannot be reached over ssh yet, which is true in a
  # container and false on a real host, so that one reason is allowed and no other.
  rc=0
  out="$(HOME="$SANDBOX" PATH="$SANDBOX/bin:$PATH" TS=0 TERMINFO=0 ACCOUNTS="" \
         AGENT_KEY="ssh-ed25519 AAAASHELLTEST test@shells" runner "$s" agents.sh 2>&1)" || rc=$?
  case "$rc" in
    0) ;;
    1) case "$out" in
         *"ssh server"*|*"ssh service"*|*"could not enable it from here"*) ;;
         *) bad "$s: agents.sh exited 1 for an undocumented reason"; sub_fail=1 ;;
       esac ;;
    *) bad "$s: agents.sh exited $rc"; printf '%s\n' "$out" | head -5 >&2; sub_fail=1 ;;
  esac
  case "$out" in *"1 key(s) added"*) ;; *) bad "$s: agents.sh did not authorize the key"; sub_fail=1 ;; esac
  # TERMINFO=0 above is not a nicety: without it this suite installs packages in the CI
  # containers, and a test that installs software on the machine running it is a bug.
  case "$out" in
    *"terminal database: skipped"*) ;;
    *) bad "$s: agents.sh ignored TERMINFO=0"; sub_fail=1 ;;
  esac

  [ "$sub_fail" = 0 ] && ok "$s: help, $(echo "$SUBS" | grep -c .) dry runs, and the bootstrap"
  rm -rf "$SANDBOX"
done

echo
[ "$FAIL" = 0 ] || { echo 'test-shells: FAILED' >&2; exit 1; }
echo 'test-shells: clean'
