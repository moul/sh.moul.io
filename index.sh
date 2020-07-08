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

More info: https://github.com/moul/sh.moul.io
EOF
}

sub_authorized_keys() {
    umask 077
    mkdir -p .ssh
    echo "" >> .ssh/authorized_keys
    echo "# https://github.com/moul.keys" >> .ssh/authorized_keys
    curl https://github.com/moul.keys >> .ssh/authorized_keys
    echo "" >> .ssh/authorized_keys
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
