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
    authorized_keys  [USER]      add keys from github.com/moul.keys into .ssh/authorized_keys
    install_brew                 install homebrew
    install_docker               use get.docker.com script to install docker
    install_go       [VERSION]   download go binary and configure path
    install_gvm                  install gvm (go version manager)
    install_hub                  install hub (with homebrew)
    install_tools                install common tools (tmux, htop, git, ssh, curl, wget, mosh, emacs)
    adduser          [USER]      create a new moul user, install SSH keys, configure docker & sudo
    info                         print system info
    docker_prune                 prune docker things
    disk_placeholder             create a /placeholder file on disk

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

GO_VERSION=${GO_VERSION:-1.15.8}

sub_install_go() {
    GO_VERSION=${1:-${GO_VERSION}}
    # FIXME: support other distributions
    # FIXME: auto-detect last version
    dest=/usr/local/
    if [ "$(uname -m)" = "x86_64" ]; then
  arch="amd64"
    else
  arch="386"
    fi
    if [ -d "$dest/go" ]; then
  echo "[-] '$dest' already exists, cannot continue."
  (
      set -x
      $dest/go/bin/go version
  )
  exit 0
    fi
    set -xe
    curl -sOL https://storage.googleapis.com/golang/go${GO_VERSION}.linux-${arch}.tar.gz
    tar -C $dest -xf go${GO_VERSION}.linux-${arch}.tar.gz
    echo 'export GOPATH=$HOME/go' >> ~/.profile
    echo 'export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin' >> ~/.profile
    $dest/go/bin/go version
    rm -f go${GO_VERSION}.linux-${arch}.tar.gz
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

sub_install_brew() {
    set -xe
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo 'eval $(/home/linuxbrew/.linuxbrew/bin/brew shellenv)' >> /home/moul/.profile
    . $(/home/linuxbrew/.linuxbrew/bin/brew shellenv)
    brew install hello
}

sub_install_gvm() {
    set -xe
    GO_VERSION=${1:-${GO_VERSION}}
    curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer | bash
    source $HOME/.gvm/scripts/gvm
    gvm install go1.4 -B
    gvm use go1.4
    GOROOT_BOOTSTRAP=$GOROOT gvm install go${GO_VERSION}
    gvm use go${GO_VERSION}
    go get moul.io/moulsay
    moulsay yo
}

sub_install_hub() {
    set -xe
    sub_install_brew
    . $(/home/linuxbrew/.linuxbrew/bin/brew shellenv)
    brew install hub
}

sub_disk_placeholder() {
    # https://brianschrader.com/archive/why-all-my-servers-have-an-8gb-empty-file/
    set -xe
    sudo truncate -s 8G /placeholder
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
