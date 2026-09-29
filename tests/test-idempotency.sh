#!/bin/sh
# test-idempotency.sh: running it twice must be the same as running it once.
#
# The version of this repo that ran until today appended every key on every run, so a
# machine set up three times had three copies of each key in authorized_keys. Nothing broke
# loudly, which is why it survived for years. This test is that bug, pinned down.
set -eu
cd "$(dirname "$0")/.."

FAIL=0
ok()  { printf ' ok  %s\n' "$*"; }
bad() { printf 'fail %s\n' "$*" >&2; FAIL=1; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin"
printf '#!/bin/sh\necho "REFUSED sudo" >&2\nexit 7\n' >"$SANDBOX/bin/sudo"
chmod +x "$SANDBOX/bin/sudo"

K1="ssh-ed25519 AAAAIDEMPOTENTONE first@test"
K2="ssh-ed25519 AAAAIDEMPOTENTTWO second@test"
AK="$SANDBOX/.ssh/authorized_keys"

# Non-zero here means "this machine cannot be reached over ssh yet", which is true inside
# a container and irrelevant to what this test is about: the file it writes.
run_once() {
  HOME="$SANDBOX" PATH="$SANDBOX/bin:$PATH" TS=0 TERMINFO=0 ACCOUNTS="" \
    AGENT_KEY="$1" sh agents.sh || true
}

run_once "$K1" >/dev/null
run_once "$K1" >/dev/null
run_once "$K2" >/dev/null
run_once "$K1" >/dev/null

[ "$(grep -c 'AAAAIDEMPOTENTONE' "$AK")" = 1 ] && ok "the first key appears once after four runs" \
  || bad "the first key appears $(grep -c 'AAAAIDEMPOTENTONE' "$AK") times"
[ "$(grep -c 'AAAAIDEMPOTENTTWO' "$AK")" = 1 ] && ok "the second key appears once" \
  || bad "the second key is wrong"
[ "$(grep -c . "$AK")" = 2 ] && ok "the file holds exactly the two keys" \
  || bad "the file holds $(grep -c . "$AK") lines"

perm="$(stat -c %a "$AK" 2>/dev/null || stat -f %Lp "$AK")"
[ "$perm" = 600 ] && ok "authorized_keys is 0600" || bad "authorized_keys is $perm"
perm="$(stat -c %a "$SANDBOX/.ssh" 2>/dev/null || stat -f %Lp "$SANDBOX/.ssh")"
[ "$perm" = 700 ] && ok ".ssh is 0700" || bad ".ssh is $perm"

# An existing file with other keys in it must survive: this runs on machines that are
# already somebody's.
printf 'ssh-rsa AAAAPREEXISTING somebody@else\n' >>"$AK"
run_once "$K1" >/dev/null
grep -q 'AAAAPREEXISTING' "$AK" && ok "a key that was already there is untouched" \
  || bad "an existing key was lost"

echo
[ "$FAIL" = 0 ] || { echo 'test-idempotency: FAILED' >&2; exit 1; }
echo 'test-idempotency: clean'
