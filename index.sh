#!/bin/sh
set -e
if [ "x$TRACE" != "x" ]; then set -x; fi

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

sub_help() {
    cat <<EOF
Usage: curl -s https://sh.moul.io | sh -s -- <subcommand> [options]

Subcommands:
    authorized_keys  [USER]   add keys from github.com/moul.keys into .ssh/authorized_keys
    install_docker            use get.docker.com script to install docker
    install_tools             install common tools (tmux, htop, git, ssh, curl, wget, mosh, emacs)
    adduser          [USER]   create a new moul user, install SSH keys, configure docker & sudo
    info                      print system info
    docker_prune              prune docker things

More info: https://github.com/moul/sh.moul.io
EOF
}

sub_authorized_keys() {
    USER=${1:-${USER}}
    set -x
    umask 077
    mkdir -p .ssh
    echo "" >> .ssh/authorized_keys
    echo "# https://github.com/${USER}.keys" >> .ssh/authorized_keys
    curl -s https://github.com/${USER}.keys >> .ssh/authorized_keys
    echo "" >> .ssh/authorized_keys
}

sub_install_docker() {
    set -x
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    # check if docker-compose is available
}

sub_install_tools() {
    # FIXME: support other distributions
    set -x
    sudo apt -y install tmux htop emacs-nox git ssh curl wget mosh
}

sub_adduser() {
    USER=${1:-moul}
    set -x
    useradd -m ${USER}
    usermod -aG docker ${USER}
    usermod --shell=/bin/bash ${USER}
    mkdir -p /home/${USER}/.ssh
    umask 077
    curl -s https://github.com/${USER}.keys | grep -v "Not Found" >> /home/${USER}/.ssh/authorized_keys
    chown -R ${USER}:${USER} /home/${USER}/.ssh
    echo "${USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
}

sub_info() {
    set -x
    set +e
    date
    uptime
    lsb_release -a
    cat /etc/debian_version
    cat /proc/cmdline
    cat /proc/loadavg
    w | grep -v tmux | head
    last | grep -v tmux | head
}

sub_docker_prune() {
    set -x
    docker system prune -f
    docker volume prune -f
}

main() {
    subcommand=$1
    case $subcommand in
        "" | "-h" | "--help")
            sub_help
            ;;
        *)
            shift
            sub_${subcommand} $@
            if [ $? = 127 ]; then
                echo "Error: '$subcommand' is not a known subcommand." >&2
                echo "       Run 'curl -s https://sh.moul.io | sh' for a list of known subcommands." >&2
            fi
            ;;
    esac
}

main "$@"
