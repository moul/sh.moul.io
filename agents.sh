#!/bin/sh
# NOT AUDITED, AI-generated tooling. Read it before running it on a machine you care about.
#
# Run this on a new machine, and nothing else:
#
#   curl -fsSL https://sh.moul.io/agents | sh
#
# It authorizes the keys, turns on remote login, joins the tailnet, and prints the one ssh
# line that reaches this machine from anywhere. It installs no tooling and touches no
# account: that all happens afterwards, over ssh, driven from somewhere else.
#
# Generic source: the host-bootstrap kit. This copy is the rendered one, with the accounts
# filled in. Edit it there, not here.
#
# Options:
#   curl ... | sh -s -- alice bob         authorize other accounts instead
#   curl ... | AGENT_KEY="ssh-ed25519 AAAA... ctl" sh    also authorize a controller's key
#   curl ... | TS=0 sh                    skip the tailnet
#   curl ... | TS_AUTHKEY="tskey-..." sh  join unattended, no browser
#   curl ... | TS_ARGS="--ssh" sh         let the tailnet authorize ssh instead of the keyfile
#
# The key endpoints are read ONCE and written to disk. They are mutable lists controlled by
# those accounts, so a machine that re-read them would hand a shell to whoever controls an
# account tomorrow. Snapshot, not subscription.

set -u

VERSION="dev"   # replaced at build time with the commit it was built from

ACCOUNTS="${ACCOUNTS:-moul gnoute42}"
TS="${TS:-auto}"
TS_AUTHKEY="${TS_AUTHKEY:-}"
TS_ARGS="${TS_ARGS:-}"
AGENT_KEY="${AGENT_KEY:-}"
[ $# -gt 0 ] && ACCOUNTS="$*"

KEYS_URLS=""
for a in $ACCOUNTS; do
  case "$a" in
    https://*) KEYS_URLS="$KEYS_URLS $a" ;;
    *)         KEYS_URLS="$KEYS_URLS https://github.com/$a.keys" ;;
  esac
done

ok()   { printf ' ok  %s\n' "$*"; }
note() { printf '     %s\n' "$*"; }
bad()  { printf 'fail %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# Under sudo this would write to root's home, which is not the account anyone logs into.
[ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] && {
  bad "run this as yourself, not with sudo: it authorizes the account you log in as"; exit 1; }

# ── 1. the keys ───────────────────────────────────────────────────────────────
AK="$HOME/.ssh/authorized_keys"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh" || exit 1
touch "$AK" && chmod 600 "$AK" || exit 1

added=0
add_key() { # by key body, so a re-run is a no-op and the comment may differ
  body=$(echo "$1" | awk '{print $2}')
  [ -n "$body" ] || return 0
  if grep -qF "$body" "$AK" 2>/dev/null; then
    note "already there: ...$(echo "$body" | tail -c 9)"
  else
    echo "$1" >>"$AK"; added=$((added + 1))
    ok "authorized: $(echo "$1" | awk '{print $1}') ...$(echo "$body" | tail -c 9)"
  fi
}

for url in $KEYS_URLS; do
  keys=$(curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 30 "$url") \
    || { bad "could not fetch $url"; exit 1; }
  [ -n "$keys" ] || { bad "$url returned nothing: is that account name right?"; exit 1; }
  n=0
  OLDIFS="$IFS"; IFS='
'
  for k in $keys; do add_key "$k"; n=$((n + 1)); done
  IFS="$OLDIFS"
  # The endpoint strips key comments, so these arrive anonymous: you cannot tell which
  # machine each one belongs to, and taking the list takes all of them.
  note "$n key(s) from $url, none of them named"
done
[ -n "$AGENT_KEY" ] && add_key "$AGENT_KEY"
ok "$added key(s) added, $(grep -c . "$AK") authorized in total"

# ── 2. remote login ───────────────────────────────────────────────────────────
sshd_up() {
  have systemsetup && systemsetup -getremotelogin 2>/dev/null | grep -qi 'on$' && return 0
  have nc && nc -z 127.0.0.1 22 >/dev/null 2>&1 && return 0
  return 1
}

if sshd_up; then
  ok "remote login already on"
elif [ "$(uname -s)" = Darwin ]; then
  sudo systemsetup -f -setremotelogin on >/dev/null 2>&1
  if sshd_up; then ok "remote login enabled"; else
    # On recent macOS this needs Full Disk Access for the terminal it runs in, which a
    # script cannot grant itself. The switch in the settings app always works.
    bad "could not enable it from here"
    note "turn it on: System Settings, General, Sharing, Remote Login. Then run this again"
  fi
elif have systemctl; then
  sudo systemctl enable --now ssh >/dev/null 2>&1 || sudo systemctl enable --now sshd >/dev/null 2>&1
  sshd_up && ok "remote login enabled" || bad "enable the ssh service by hand"
else
  bad "enable the ssh server by hand, then run this again"
fi

# ── 3. the tailnet ────────────────────────────────────────────────────────────
# Without it the machine is reachable only from the network it was unboxed on, which is
# exactly what fails the first time it is set up somewhere else.
TS_NAME=""; TS_IP=""
ts_joined() { have tailscale && tailscale status >/dev/null 2>&1; }

if [ "$TS" = 0 ]; then
  note "tailnet: skipped"
elif ts_joined; then
  ok "tailnet: already joined"
else
  if ! have tailscale; then
    if have brew; then
      brew install tailscale >/dev/null 2>&1 && sudo tailscaled install-system-daemon >/dev/null 2>&1
    elif [ "$(uname -s)" = Linux ]; then
      curl -fsSL https://tailscale.com/install.sh | sh
    fi
  fi
  if have tailscale; then
    note "a browser page will open, or a URL will be printed: approve this machine there"
    # shellcheck disable=SC2086
    if [ -n "$TS_AUTHKEY" ]; then
      sudo tailscale up --authkey "$TS_AUTHKEY" $TS_ARGS
    else
      sudo tailscale up $TS_ARGS
    fi
    ts_joined && ok "tailnet: joined" || bad "tailnet: join did not complete"
  elif [ "$TS" = 1 ]; then
    bad "no way to install the tailnet client here"
    note "macOS without a package manager: install the app, then run this again"
    exit 1
  else
    note "tailnet: no client and no package manager yet, skipped"
    note "it can be installed later over ssh"
  fi
fi

if ts_joined; then
  TS_NAME=$(tailscale status --json 2>/dev/null | sed -n 's/.*"DNSName": *"\([^"]*\)\..*/\1/p' | head -1)
  TS_IP=$(tailscale ip -4 2>/dev/null | head -1)
fi

# ── 4. how to get in ──────────────────────────────────────────────────────────
echo
ok "done. From here on this machine is driven from somewhere else:"
echo
if [ -n "$TS_NAME" ]; then
  printf '       ssh %s@%s\n' "$(id -un)" "$TS_NAME"
  [ -n "$TS_IP" ] && printf '       ssh %s@%s   (if the name does not resolve yet)\n' "$(id -un)" "$TS_IP"
elif [ -n "$TS_IP" ]; then
  printf '       ssh %s@%s\n' "$(id -un)" "$TS_IP"
else
  printf '       ssh %s@%s   (same network only)\n' "$(id -un)" "$(hostname 2>/dev/null || uname -n)"
  if have ipconfig; then
    for i in $(ipconfig getiflist 2>/dev/null); do
      a=$(ipconfig getifaddr "$i" 2>/dev/null) || continue
      [ -n "$a" ] && printf '       ssh %s@%s   (%s)\n' "$(id -un)" "$a" "$i"
    done
  fi
fi
echo
note "nothing else needs typing here"
note "(this script was built from $VERSION)"
