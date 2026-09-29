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
#   curl ... | TERMINFO=0 sh               skip the terminal database step
#   curl ... | TS_AUTHKEY="tskey-..." sh  join unattended, no browser
#   curl ... | TS_ARGS="--ssh" sh         let the tailnet authorize ssh instead of the keyfile
#
# The key endpoints are read ONCE and written to disk. They are mutable lists controlled by
# those accounts, so a machine that re-read them would hand a shell to whoever controls an
# account tomorrow. Snapshot, not subscription.

set -u

VERSION="dev"   # replaced at build time with the commit it was built from

# Unset means the defaults. Explicitly empty means none, which is how you ask for a
# machine that trusts only the key you pass by hand.
ACCOUNTS="${ACCOUNTS-moul gnoute42}"
TS="${TS:-auto}"
TERMINFO="${TERMINFO:-auto}"
TERMINFO_TERMS="${TERMINFO_TERMS:-xterm-kitty xterm-ghostty}"
TERMINFO_PKGS="${TERMINFO_PKGS:-kitty-terminfo ncurses-term}"
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

# Root has no use for sudo, and a container usually has no sudo binary at all.
SUDO=""
[ "$(id -u)" = 0 ] || SUDO="sudo"

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
# The whole point is to reach this machine later, so failing to turn this on is a failure
# of the script, not a note in passing. Everything still runs, and the exit code says so.
RC=0
sshd_up() {
  # macOS answers authoritatively.
  have systemsetup && systemsetup -getremotelogin 2>/dev/null | grep -qi 'on$' && return 0
  # On Linux, ask the kernel what is listening rather than trying to connect.
  have ss && ss -ltn 2>/dev/null | grep -qE '[:.]22[[:space:]]' && return 0
  have netstat && netstat -ltn 2>/dev/null | grep -qE '[:.]22[[:space:]]' && return 0
  # Last resort, open a connection. Not `nc -z`: busybox nc has no such flag, so that
  # check reports "no ssh here" on every busybox system, which is most minimal images.
  have nc && nc -w 2 127.0.0.1 22 </dev/null >/dev/null 2>&1 && return 0
  return 1
}

if sshd_up; then
  ok "remote login already on"
elif [ "$(uname -s)" = Darwin ]; then
  $SUDO systemsetup -f -setremotelogin on >/dev/null 2>&1
  if sshd_up; then ok "remote login enabled"; else
    # On recent macOS this needs Full Disk Access for the terminal it runs in, which a
    # script cannot grant itself. The switch in the settings app always works.
    bad "could not enable it from here"
    note "turn it on: System Settings, General, Sharing, Remote Login. Then run this again"
    RC=1
  fi
elif have systemctl; then
  $SUDO systemctl enable --now ssh >/dev/null 2>&1 || $SUDO systemctl enable --now sshd >/dev/null 2>&1
  if sshd_up; then ok "remote login enabled"; else bad "enable the ssh service by hand"; RC=1; fi
else
  bad "no ssh server here, and no way to start one: enable it by hand"
  RC=1
fi

# ── 3. the terminal database ──────────────────────────────────────────────────
# tmux, and everything else built on curses, refuses to start when TERM names a terminal the
# machine has never heard of: "missing or unsuitable terminal: xterm-kitty". TERM arrives
# from the CLIENT over ssh, so a kitty or ghostty user reaches a brand new machine and the
# first thing they type is the thing that breaks. The package manager carries these entries.
#
# This cannot be complete from here and is not meant to be: only the client has the terminfo
# for a terminal this machine's distribution does not package, or for any terminal at all on
# macOS. So when an entry is still missing, print the command that copies it from there.
# Never fake the entry by aliasing it to xterm-256color: that silently drops the graphics
# protocol and styled underlines, and nobody ever connects the loss back to this script.
term_missing() {
  m=""
  for t in $TERMINFO_TERMS; do
    infocmp "$t" >/dev/null 2>&1 || m="$m $t"
  done
  printf '%s' "$m"
}

if [ "$TERMINFO" = 0 ]; then
  note "terminal database: skipped"
else
  missing="$(term_missing)"
  if [ -n "$missing" ]; then
    # shellcheck disable=SC2086
    if have apt-get; then $SUDO apt-get install -y $TERMINFO_PKGS >/dev/null 2>&1
    elif have dnf; then $SUDO dnf install -y $TERMINFO_PKGS >/dev/null 2>&1
    elif have pacman; then $SUDO pacman -Sy --noconfirm $TERMINFO_PKGS >/dev/null 2>&1
    elif have apk; then $SUDO apk add --no-cache $TERMINFO_PKGS >/dev/null 2>&1
    fi
    missing="$(term_missing)"
  fi
  if [ -z "$missing" ]; then
    ok "terminal database knows:$TERMINFO_TERMS"
  else
    note "terminal database does not know:$missing"
    note 'tmux over ssh will refuse with "missing or unsuitable terminal"'
    note "fix from the machine you ssh FROM, no root needed on either side:"
    for t in $missing; do
      note "  infocmp -a $t | ssh $(id -un)@<this host> 'mkdir -p ~/.terminfo && tic -x -o ~/.terminfo /dev/stdin'"
    done
  fi
fi

# ── 4. the tailnet ────────────────────────────────────────────────────────────
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
      brew install tailscale >/dev/null 2>&1 && $SUDO tailscaled install-system-daemon >/dev/null 2>&1
    elif [ "$(uname -s)" = Linux ]; then
      ts_tmp="$(mktemp)"
      if curl -fsSL --proto '=https' --max-time 60 https://tailscale.com/install.sh -o "$ts_tmp"; then
        sh "$ts_tmp"
      fi
      rm -f "$ts_tmp"
    fi
  fi
  if have tailscale; then
    note "a browser page will open, or a URL will be printed: approve this machine there"
    # shellcheck disable=SC2086
    if [ -n "$TS_AUTHKEY" ]; then
      $SUDO tailscale up --authkey "$TS_AUTHKEY" $TS_ARGS
    else
      $SUDO tailscale up $TS_ARGS
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

# ── 5. how to get in ──────────────────────────────────────────────────────────
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

# Non-zero when this machine cannot actually be reached yet, so anything driving it knows.
exit "$RC"
