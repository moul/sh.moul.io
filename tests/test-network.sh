#!/bin/sh
# test-network.sh: the endpoints this repo sends people to are still there.
#
# Separate from the rest because it needs the internet and depends on other people's
# infrastructure. It is the rot detector: the old version of this repo pointed at a Go
# download path and a version from 2022, and nothing noticed for years. Run on a schedule,
# not as a gate on every change.
set -eu
cd "$(dirname "$0")/.."

FAIL=0
ok()   { printf ' ok  %s\n' "$*"; }
bad()  { printf 'fail %s\n' "$*" >&2; FAIL=1; }
warn() { printf 'warn %s\n' "$*" >&2; }

reachable() { curl -fsSL --proto '=https' --connect-timeout 10 --max-time 30 -o /dev/null "$1"; }

for url in \
  https://github.com/moul.keys \
  https://github.com/gnoute42.keys \
  https://get.docker.com \
  https://tailscale.com/install.sh \
  https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
do
  reachable "$url" && ok "reachable: $url" || bad "unreachable: $url"
done

keys="$(curl -fsSL --max-time 30 https://github.com/moul.keys | grep -c . || echo 0)"
[ "$keys" -gt 0 ] && ok "the key endpoint serves $keys key(s)" \
  || bad "the key endpoint serves nothing, so a bootstrap would authorize nobody"

version="$(curl -fsSL --max-time 30 'https://go.dev/VERSION?m=text' | head -1)"
case "$version" in
  go[0-9]*) ok "the Go version endpoint answers: $version" ;;
  *)        bad "the Go version endpoint answered '$version', which is not a version" ;;
esac

# Every architecture this is likely to meet must have a build at the URL we construct.
for pair in linux-amd64 linux-arm64 darwin-arm64 darwin-amd64; do
  goos="${pair%-*}"; goarch="${pair#*-}"
  curl -fsSI --max-time 30 "https://go.dev/dl/$version.$goos-$goarch.tar.gz" >/dev/null 2>&1 \
    && ok "there is a Go build for $pair" || bad "no Go build for $pair at the URL we build"
done

# Production, once it is deployed. A pull request that has not merged yet will not have it.
if reachable https://sh.moul.io/agents; then
  ok "https://sh.moul.io/agents is live"
  curl -fsSL --max-time 30 https://sh.moul.io/agents | grep -q 'VERSION=' \
    && ok "the live copy carries a version stamp" || warn "the live copy has no version stamp yet"
else
  warn "https://sh.moul.io/agents is not live yet (expected before the first deploy)"
fi

echo
[ "$FAIL" = 0 ] || { echo 'test-network: FAILED' >&2; exit 1; }
echo 'test-network: clean'
