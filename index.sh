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
    authorized_keys     add keys from github.com/moul.keys into .ssh/authorized_keys
    install_docker      use get.docker.com script to install docker
    install_tools       install common tools (tmux, htop, git, ssh, curl, wget, mosh, emacs)
    adduser             create a new moul user, install SSH keys, configure docker & sudo
    info                print system info

More info: https://github.com/moul/sh.moul.io
EOF
}

sub_authorized_keys() {
    # FIXME: support other $USER
    umask 077
    mkdir -p .ssh
    echo "" >> .ssh/authorized_keys
    echo "# https://github.com/moul.keys" >> .ssh/authorized_keys
    curl https://github.com/moul.keys >> .ssh/authorized_keys
    echo "" >> .ssh/authorized_keys
}

sub_install_docker() {
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    # check if docker-compose is available
}

sub_install_tools() {
    # FIXME: support other distributions
    sudo apt install tmux htop emacs-nox git ssh curl wget mosh
}

sub_adduser() {
    # FIXME: support other $USER
    useradd -m moul
    usermod -aG docker moul
    usermod --shell=/bin/bash moul
    mkdir -p /home/moul/.ssh
    umask 077
    curl https://github.com/moul.keys >> /home/moul/.ssh/authorized_keys
    chown -R moul:moul /home/moul/.ssh
    echo "moul ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
}

sub_info() {
    set -x
    date
    uptime
    lsb_release -a
    cat /proc/cmdline
    cat /proc/loadavg
    w | grep -v tmux | head
    last | grep -v tmux | head
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
