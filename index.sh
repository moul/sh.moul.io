#!/bin/sh
# sh.moul.io: the things I run when I arrive on a new machine.
#
#   curl -fsSL https://sh.moul.io | sh                      list the subcommands
#   curl -fsSL https://sh.moul.io | sh -s -- <sub> [args]   run one
#   curl -fsSL https://sh.moul.io | DRY=1 sh -s -- <sub>    print what it would do
#
# NOT AUDITED. It is a shell script from the internet that installs software: read it first.
# Source: https://github.com/moul/sh.moul.io
set -eu
[ "${TRACE:-}" = "" ] || set -x

VERSION="dev"   # replaced at build time with the commit it was built from

#       ++
#       ++++
#        ++++
#      ++++++++++
#     +++       |
#     ++         |
#     +  -==   ==|
#    (   <*>   <*>
#     |           |
#     |         __|
#     |      +++
#      \      =+
#       \      +                           more info here:
#       |\++++++                  https://github.com/moul/sh.moul.io
#       |  ++++      ||//
#   ____|   |____   _||/__
#  /     ---     \  \|  |||
# /  _ _  _     / \   \ /
# | / / //_//_//  |   | |

ok()   { printf ' ok  %s\n' "$*"; }
note() { printf '     %s\n' "$*"; }
bad()  { printf 'fail %s\n' "$*" >&2; }
die()  { bad "$*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Everything that changes the machine goes through this, so DRY=1 previews the whole thing.
run() {
  if [ "${DRY:-0}" = 1 ]; then printf 'dry  %s\n' "$*"; return 0; fi
  printf ' run %s\n' "$*"
  "$@"
}

# Root has no use for sudo, and a container usually has no sudo binary at all. A fresh
# server where you are already root is the oldest use case this file has.
SUDO=""
[ "$(id -u)" = 0 ] || SUDO="sudo"

os()  { case "$(uname -s)" in Darwin) echo macos ;; Linux) echo linux ;; *) echo other ;; esac; }
arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo amd64 ;;
    aarch64|arm64) echo arm64 ;;   # the case the old version of this file got wrong
    armv7l|armv6l) echo armv6l ;;
    i386|i686)     echo 386 ;;
    *)             uname -m ;;
  esac
}
pkg() {
  if have brew; then echo brew
  elif have apt-get; then echo apt
  elif have dnf; then echo dnf
  elif have apk; then echo apk
  elif have pacman; then echo pacman
  else echo none; fi
}
# Can the privileged path work at all, right now, without a human? Three ways yes:
# already root, passwordless sudo, or a terminal a person can type a password on. Asking
# this BEFORE reaching for the package manager is the difference between a useful fallback
# and a wall of sudo errors.
can_sudo() {
  [ "$(id -u)" = 0 ] && return 0
  have sudo || return 1
  sudo -n true 2>/dev/null && return 0
  (: </dev/tty) 2>/dev/null && return 0
  return 1
}

# Debian names the package, not always the binary.
binname() {
  case "$1" in
    ripgrep) echo rg ;;
    fd-find) echo fdfind ;;
    *)       echo "$1" ;;
  esac
}

pkg_install() {
  case "$(pkg)" in
    brew)   run brew install "$@" ;;
    apt)    run $SUDO apt-get update -qq; run $SUDO apt-get install -y "$@" ;;
    dnf)    run $SUDO dnf install -y "$@" ;;
    apk)    run $SUDO apk add --no-cache "$@" ;;
    pacman) run $SUDO pacman -Sy --noconfirm "$@" ;;
    *)      die "no package manager found: install these by hand: $*" ;;
  esac
}

# ── subcommands ───────────────────────────────────────────────────────────────
# One line each, "name<TAB>args<TAB>description". The help is generated from this, so it
# cannot drift from what actually exists, and a test checks both directions.
SUBCOMMANDS='
agents|[ACCOUNTS...]|set up a machine an agent will drive: keys, remote login, tailnet
authorized_keys|[ACCOUNTS...]|add github.com/<account>.keys to ~/.ssh/authorized_keys
install_tools|[PKGS...]|tmux, htop, git, curl, wget, mosh, jq, ripgrep, or what you name
install_brew|"|the package manager, on macOS or Linux
install_docker|"|via get.docker.com
install_go|[VERSION]|the latest Go, or the one you name, with the right architecture
info|"|what this machine is
docker_prune|"|reclaim docker disk
disk_placeholder|[SIZE]|a file to delete when the disk fills up at 3am
'

sub_help() {
  cat <<EOF
Usage: curl -fsSL https://sh.moul.io | sh -s -- <subcommand> [options]

Subcommands:
EOF
  echo "$SUBCOMMANDS" | grep . | while IFS='|' read -r name args desc; do
    [ "$args" = '"' ] && args=""
    printf '    %-18s %-14s %s\n' "$name" "$args" "$desc"
  done
  cat <<EOF

Anything mutating honours DRY=1, which prints instead of doing.
Built from: $VERSION
More info: https://github.com/moul/sh.moul.io
EOF
}

# The one that matters: a new machine, authorized and reachable, and nothing else.
sub_agents() {
  if [ "${DRY:-0}" = 1 ]; then note "dry  fetch https://sh.moul.io/agents and run it with: $*"; return 0; fi
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
  curl -fsSL --proto '=https' --connect-timeout 10 --max-time 60 https://sh.moul.io/agents -o "$tmp" \
    || die "could not fetch /agents"
  sh "$tmp" "$@"
}

sub_authorized_keys() {
  [ $# -gt 0 ] || set -- moul
  AK="$HOME/.ssh/authorized_keys"
  run mkdir -p "$HOME/.ssh"
  run chmod 700 "$HOME/.ssh"
  [ "${DRY:-0}" = 1 ] || { touch "$AK"; chmod 600 "$AK"; }
  for account in "$@"; do
    keys="$(curl -fsSL --connect-timeout 10 "https://github.com/$account.keys")" \
      || die "could not read the keys of $account"
    [ -n "$keys" ] || die "$account has no public keys"
    echo "$keys" | while IFS= read -r key; do
      [ -n "$key" ] || continue
      body="$(echo "$key" | awk '{print $2}')"
      # By key body, so running this twice does not write the same key twice, which is
      # what the previous version of this script did every single time.
      if grep -qsF "$body" "$AK"; then
        note "already there: $account ...$(echo "$body" | tail -c 9)"
      elif [ "${DRY:-0}" = 1 ]; then
        note "dry  authorize $account ...$(echo "$body" | tail -c 9)"
      else
        printf '%s # %s, added %s\n' "$key" "$account" "$(date +%F)" >>"$AK"
        ok "authorized $account ...$(echo "$body" | tail -c 9)"
      fi
    done
  done
}

sub_install_tools() {
  [ $# -gt 0 ] || set -- tmux htop git curl wget mosh jq ripgrep
  missing=""
  for p in "$@"; do
    have "$(binname "$p")" || missing="$missing $p"
  done
  [ -n "$missing" ] || { ok "already installed: $*"; return 0; }

  if can_sudo; then
    # shellcheck disable=SC2086
    pkg_install $missing
    return $?
  fi

  # The common case for this file is a machine being set up by something that is not at its
  # keyboard, so there is no password and no terminal to type one on. Failing here means the
  # host sits toolless until a human is free. Most of these do not actually need root.
  note "no root and no terminal to ask for a password: using a user prefix instead"
  # shellcheck disable=SC2086
  install_unprivileged $missing
}

# ── the unprivileged route ────────────────────────────────────────────────────
# Only `apt-get install` needs root: it writes outside $HOME and owns the package database.
# `apt-get download` and `dpkg-deb -x` need nothing, so a package whose dependencies are
# already satisfied can be unpacked under ~/.local and symlinked onto PATH.
#
# It does NOT resolve dependencies, deliberately. Unpacking a dependency tree into a user
# prefix by hand gives you a binary that loads the wrong libc at the worst possible moment,
# so an unmet dependency is reported and skipped rather than worked around.
install_unprivileged() {
  rc=0
  for p in "$@"; do
    b="$(binname "$p")"
    case "$(os)" in
      linux)  deb_unpack "$p" "$b" || rc=1 ;;
      macos)  user_brew "$p" || rc=1 ;;
      *)      bad "$p: no unprivileged route on this platform"; rc=1 ;;
    esac
  done
  note "still needs a human: anything installing a system service, and privileged prefixes"
  return "$rc"
}

deb_unpack() {
  p="$1"; b="$2"
  have apt-get && have dpkg-deb || { bad "$p: needs apt-get and dpkg-deb"; return 1; }
  prefix="$HOME/.local/opt/deb"; bindir="$HOME/.local/bin"
  if [ "${DRY:-0}" = 1 ]; then
    note "dry  apt-get download $p, then dpkg-deb -x into $prefix, then link $bindir/$b"
    return 0
  fi
  d="$(mktemp -d)" || return 1
  out="$( ( set -e
    cd "$d"
    apt-get download "$p" >/dev/null 2>&1
    deb="$(ls ./*.deb 2>/dev/null | head -1)"
    [ -n "$deb" ]
    missing=""
    for dep in $(dpkg-deb -f "$deb" Depends 2>/dev/null | tr ',' '\n' | awk '{print $1}'); do
      dpkg -s "$dep" >/dev/null 2>&1 || missing="$missing $dep"
    done
    [ -z "$missing" ] || { echo "unmet:$missing"; exit 2; }
    mkdir -p "$prefix" "$bindir"
    dpkg-deb -x "$deb" "$prefix"
    found="$(find "$prefix" -type f -perm -u+x -name "$b" | head -1)"
    [ -n "$found" ]
    ln -sf "$found" "$bindir/$b"
    # Verify through the link. A link into a temp dir that is about to be deleted resolves
    # to nothing, and the first version of this reported success anyway.
    [ -x "$bindir/$b" ]
  ) 2>&1 )"
  r=$?
  rm -rf "$d"
  case "$r" in
    0) ok "$p, unpacked into $prefix and linked as $bindir/$b" ;;
    2) bad "$p needs root: missing${out#unmet:}" ;;
    *) bad "$p: could not unpack"; [ -n "$out" ] && note "$out" ;;
  esac
  [ "$r" = 0 ]
}

user_brew() {
  p="$1"
  if [ -x "$HOME/homebrew/bin/brew" ]; then
    if [ "${DRY:-0}" = 1 ]; then note "dry  $HOME/homebrew/bin/brew install $p"; return 0; fi
    # `brew shellenv` is the documented way in, but it is meant to be eval'd and this repo
    # bans eval. brew derives its prefix from its own location, so putting it on PATH is
    # all it actually needs from that output.
    PATH="$HOME/homebrew/bin:$PATH"; export PATH
    run brew install "$p"
    return $?
  fi
  bad "$p: no user-prefix Homebrew yet. Run install_brew first"
  return 1
}

sub_install_brew() {
  have brew && { ok "already installed: $(brew --version | head -1)"; return 0; }
  # A user-prefix install is not on PATH in a non-interactive shell, so `have brew` misses
  # it. Without this check a re-run reinstalls Homebrew on a machine that already has it,
  # which is exactly what an unattended second pass does.
  if [ -x "$HOME/homebrew/bin/brew" ]; then
    ok "already installed: $("$HOME/homebrew/bin/brew" --version | head -1), in $HOME/homebrew"
    return 0
  fi
  if [ "${DRY:-0}" = 1 ]; then
    note "dry  fetch the Homebrew installer and run it, then put it on PATH for login shells"
    return 0
  fi
  # Fetch, then run. The usual one-liner substitutes the download inside the command, so
  # the script is fetched even when you only meant to look at what would happen.
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
  curl -fsSL --proto '=https' --connect-timeout 10 --max-time 120 \
    https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$tmp" || die "download failed"
  # Homebrew needs a terminal to ask for the sudo password. Piped from a URL, stdin IS this
  # script, so Homebrew sees no tty, puts itself in non-interactive mode, and that mode wants
  # passwordless sudo. What surfaces is "Insufficient permissions to install Homebrew to
  # /opt/homebrew", which reads like an ownership problem and sends you to the wrong place.
  # Hand it the real terminal. The session has one even when this script's stdin does not.
  if (: </dev/tty) 2>/dev/null; then
    /bin/bash "$tmp" </dev/tty
  elif [ "$(id -u)" = 0 ] || sudo -n true 2>/dev/null; then
    # Root reaches here in containers that have no sudo binary at all. Let Homebrew speak
    # for itself: it refuses to run as root, and its own reason is more accurate than a
    # guess from here about passwords.
    /bin/bash "$tmp"
  else
    # No terminal and no passwordless sudo. The official installer cannot proceed: it wants
    # /opt/homebrew, which needs root. Homebrew does support another prefix, though, and a
    # user-writable one needs no privilege at all, so an unattended setup is not stuck.
    #
    # The trade-off, stated because it is the whole reason this is not the default: a
    # non-default prefix gets no bottles, so formulae build from source. Minutes instead of
    # seconds, and it needs the compiler toolchain present. Still beats waiting for a human.
    note "no terminal and no passwordless sudo, so /opt/homebrew is out of reach"
    note "installing into $HOME/homebrew instead, which needs no privilege"
    note "formulae will BUILD FROM SOURCE there: no bottles outside the default prefix"
    brew_user_prefix || return 1
  fi
  # The old version wrote this to one hardcoded home directory, which worked for exactly
  # one machine. Find the prefix, write to the profile of whoever is running.
  for prefix in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew "$HOME/homebrew"; do
    [ -x "$prefix/bin/brew" ] || continue
    profile="$HOME/.profile"; [ "$(os)" = macos ] && profile="$HOME/.zprofile"
    if grep -qs 'brew shellenv' "$profile"; then
      note "already on PATH for login shells"
    elif [ "${DRY:-0}" = 1 ]; then
      note "dry  add the brew environment to $profile"
    else
      printf '\neval "$(%s/bin/brew shellenv)"\n' "$prefix" >>"$profile"
      ok "added to $profile"
    fi
    # The login profile is not the file `ssh host cmd` reads, and that is how anything
    # driving this machine will run brew. On zsh a non-interactive non-login shell reads
    # ~/.zshenv and nothing else, so a PATH that only exists in ~/.zprofile makes every
    # installed tool report as absent to automation while working fine by hand.
    if [ "$(os)" = macos ] && [ "${DRY:-0}" != 1 ]; then
      if grep -qs 'brew shellenv' "$HOME/.zshenv"; then
        note "already on PATH for non-interactive shells"
      else
        printf '\neval "$(%s/bin/brew shellenv)"\n' "$prefix" >>"$HOME/.zshenv"
        ok "added to $HOME/.zshenv, so ssh <host> <cmd> sees it too"
      fi
    fi
    break
  done
}

# Homebrew in a user-writable prefix. Its own installer only targets the privileged
# prefixes, so this is the documented clone-anywhere path rather than anything exotic.
brew_user_prefix() {
  dest="$HOME/homebrew"
  if [ -x "$dest/bin/brew" ]; then ok "already installed: $dest"; return 0; fi
  if [ "${DRY:-0}" = 1 ]; then note "dry  git clone Homebrew into $dest, then brew update"; return 0; fi
  have git || die "git is needed to install Homebrew into a user prefix"
  run git clone --depth=1 https://github.com/Homebrew/brew "$dest" || return 1
  PATH="$dest/bin:$PATH"; export PATH
  # --force because a shallow clone is not what brew expects to update from.
  "$dest/bin/brew" update --force --quiet >/dev/null 2>&1 || note "brew update complained, continuing"
  ok "installed: $("$dest/bin/brew" --version | head -1) in $dest"
}

sub_install_docker() {
  have docker && { ok "already installed: $(docker --version)"; return 0; }
  if [ "${DRY:-0}" = 1 ]; then note "dry  fetch get.docker.com and run it"; return 0; fi
  # A temp file with a predictable name in a shared directory is somebody else's symlink.
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
  curl -fsSL --proto '=https' --connect-timeout 10 --max-time 120 https://get.docker.com -o "$tmp" \
    || die "download failed"
  sh "$tmp"
}

sub_install_go() {
  version="${1:-}"
  if [ "${DRY:-0}" = 1 ] && [ -z "$version" ]; then
    note "dry  resolve the latest version, then install it for $(os)-$(arch) into /usr/local"
    return 0
  fi
  if [ -z "$version" ]; then
    # The old version pinned a release from 2022. Ask upstream what is current instead.
    version="$(curl -fsSL --proto '=https' --connect-timeout 10 --max-time 30 \
      'https://go.dev/VERSION?m=text' | head -1)" || die "could not resolve the latest version"
  fi
  case "$version" in go*) ;; *) version="go$version" ;; esac
  goos="$(os)"; [ "$goos" = macos ] && goos=darwin
  tarball="$version.$goos-$(arch).tar.gz"

  if have go; then
    ok "already installed: $(go version)"
    note "to replace it: rm -rf /usr/local/go, then run this again"
    return 0
  fi
  if [ "${DRY:-0}" = 1 ]; then note "dry  install $tarball into /usr/local"; return 0; fi
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  curl -fsSL --proto '=https' --connect-timeout 10 --max-time 600 "https://go.dev/dl/$tarball" -o "$tmp/go.tar.gz" \
    || die "no such build: $tarball"
  run $SUDO rm -rf /usr/local/go
  run $SUDO tar -C /usr/local -xf "$tmp/go.tar.gz"
  profile="$HOME/.profile"; [ "$(os)" = macos ] && profile="$HOME/.zprofile"
  if ! grep -qs '/usr/local/go/bin' "$profile"; then
    printf '\nexport PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"\n' >>"$profile"
    ok "added Go to PATH in $profile"
  fi
  ok "$(/usr/local/go/bin/go version)"
}

sub_info() {
  printf 'host      %s\n' "$(hostname 2>/dev/null || uname -n)"
  printf 'os        %s %s (%s)\n' "$(uname -s)" "$(uname -r)" "$(arch)"
  # shellcheck source=/dev/null  # a file on the machine being described, not in this repo
  [ -r /etc/os-release ] && printf 'distro    %s\n' "$(. /etc/os-release && echo "$PRETTY_NAME")"
  [ "$(os)" = macos ] && printf 'macos     %s\n' "$(sw_vers -productVersion 2>/dev/null)"
  printf 'uptime    %s\n' "$(uptime | sed 's/^ *//')"
  printf 'disk      %s free\n' "$(df -h / | awk 'NR==2 {print $4}')"
  printf 'pkg mgr   %s\n' "$(pkg)"
  for t in git go docker tailscale claude; do
    have "$t" && printf '%-9s %s\n' "$t" "$(command -v "$t")"
  done
  printf 'script    %s\n' "$VERSION"
}

sub_docker_prune() {
  # A dry run is a plan, and a plan can be shown for software that is not installed yet.
  # Only a real run needs the tool to exist.
  if [ "${DRY:-0}" = 1 ]; then
    have docker || note "docker is not installed here, so a real run would stop"
  else
    have docker || die "no docker here"
  fi
  run docker system prune -f
  run docker volume prune -f
}

sub_disk_placeholder() {
  # A file you can delete at 3am when the disk is full and nothing will start.
  # https://brianschrader.com/archive/why-all-my-servers-have-an-8gb-empty-file/
  size="${1:-8G}"
  [ -e /placeholder ] && { ok "/placeholder already exists ($(du -h /placeholder | cut -f1))"; return 0; }
  run $SUDO truncate -s "$size" /placeholder
}

main() {
  case "${1:-}" in
    ""|-h|--help|help) sub_help; return 0 ;;
  esac
  sub="$1"; shift
  if ! command -v "sub_$sub" >/dev/null 2>&1; then
    bad "'$sub' is not a subcommand"
    note "run: curl -fsSL https://sh.moul.io | sh"
    return 1
  fi
  "sub_$sub" "$@"
}

main "$@"
