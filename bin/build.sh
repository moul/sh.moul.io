#!/bin/sh
# Netlify build. Produces public/, which is what gets served.
#
# Two things it does beyond copying: it stamps the commit into each script, so anyone can
# tell which version they piped into a shell, and it publishes each script under a clean
# extensionless path as well as its real name.
set -eu
cd "$(dirname "$0")/.."

STAMP="${COMMIT_REF:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}"
STAMP="$(echo "$STAMP" | cut -c1-12)"

rm -rf public
mkdir -p public

stamp() { sed "s|^VERSION=\"dev\"|VERSION=\"$STAMP\"|" "$1" >"$2"; chmod 755 "$2"; }

stamp index.sh  public/index.html    # Netlify serves / from index.html, as text/plain
stamp index.sh  public/index.sh
stamp agents.sh public/agents        # curl -fsSL https://sh.moul.io/agents | sh
stamp agents.sh public/agents.sh
cp favicon.ico public/ 2>/dev/null || true

echo "built $STAMP:"
ls -l public
