#!/bin/sh
# test-serve.sh: what a machine actually receives.
#
# Everything else tests the files in the repo. This one builds the site, serves it, fetches
# it over http the way a new machine would, and runs what came back. The gap between "the
# script in git is fine" and "the URL serves something that works" is where the real
# failures live: a build that forgets a file, a stamp that never got substituted, a path
# that only exists locally.
set -eu
cd "$(dirname "$0")/.."

FAIL=0
ok()  { printf ' ok  %s\n' "$*"; }
bad() { printf 'fail %s\n' "$*" >&2; FAIL=1; }

command -v python3 >/dev/null || { echo "python3 is needed to serve the built site" >&2; exit 1; }

./bin/build.sh >/dev/null
PORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
( cd public && exec python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 ) &
SERVER=$!
SANDBOX="$(mktemp -d)"
trap 'kill "$SERVER" 2>/dev/null || true; rm -rf "$SANDBOX"' EXIT

# Wait for it rather than sleeping and hoping.
i=0
while [ "$i" -lt 50 ]; do
  curl -fsS "http://127.0.0.1:$PORT/agents" >/dev/null 2>&1 && break
  i=$((i + 1)); sleep 0.1
done
[ "$i" -lt 50 ] || { bad "the test server never came up"; exit 1; }

for path in agents agents.sh index.sh index.html; do
  curl -fsS "http://127.0.0.1:$PORT/$path" >/dev/null 2>&1 \
    && ok "served: /$path" || bad "not served: /$path"
done

curl -fsS "http://127.0.0.1:$PORT/agents" -o "$SANDBOX/agents"
cmp -s "$SANDBOX/agents" public/agents && ok "what is fetched matches what was built" \
  || bad "the fetched file differs from the built one"

grep -q 'VERSION="dev"' "$SANDBOX/agents" && bad "the served file still says dev" \
  || ok "the served file carries a real version"

curl -fsS "http://127.0.0.1:$PORT/" | grep -q 'Subcommands:' \
  && ok "the root serves the subcommand list" || bad "the root serves something else"

# The thing that matters: run what the wire handed us.
mkdir -p "$SANDBOX/home/bin"
printf '#!/bin/sh\necho "REFUSED sudo" >&2\nexit 7\n' >"$SANDBOX/home/bin/sudo"
chmod +x "$SANDBOX/home/bin/sudo"
rc=0
out="$(HOME="$SANDBOX/home" PATH="$SANDBOX/home/bin:$PATH" TS=0 ACCOUNTS="" \
       AGENT_KEY="ssh-ed25519 AAAASERVEDRUN served@test" sh "$SANDBOX/agents" 2>&1)" || rc=$?
case "$rc" in
  0|1) ;;  # 1 is "this machine cannot be reached over ssh yet", which a sandbox is
  *)   bad "the served bootstrap exited $rc"; printf '%s\n' "$out" | head -5 >&2 ;;
esac
case "$out" in
  *"1 key(s) added"*) ok "the served bootstrap runs and authorizes a key" ;;
  *)                  bad "the served bootstrap did not authorize the key" ;;
esac
case "$out" in *"REFUSED sudo"*) bad "the served bootstrap called sudo" ;; esac

# Headers are Netlify's job, not the test server's, so check they are declared.
grep -q 'text/plain' netlify.toml && ok "plain text is declared for the served files" \
  || bad "netlify.toml does not serve these as text/plain"
grep -q 'max-age=60' netlify.toml && ok "a short cache is declared" \
  || bad "netlify.toml does not keep the cache short, so a fix cannot reach the next machine"

echo
[ "$FAIL" = 0 ] || { echo 'test-serve: FAILED' >&2; exit 1; }
echo 'test-serve: clean'
