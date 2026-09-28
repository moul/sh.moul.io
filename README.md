# [sh.moul.io](https://sh.moul.io)

[![Netlify Status](https://api.netlify.com/api/v1/badges/25622023-5703-42ff-9b10-3d7ad75db31a/deploy-status)](https://app.netlify.com/sites/sh-moul-io/deploys)

The things I run when I arrive on a new machine, served as plain text so I can read them
before I pipe them into a shell.

## The one that matters

```sh
curl -fsSL https://sh.moul.io/agents | sh
```

Run it on a **new machine**, and nothing else. It authorizes my keys, turns on remote login,
joins the machine to my tailnet, and prints the single `ssh` line that reaches it from
anywhere. It installs no tooling and touches no account: everything after that is driven
over ssh from a machine I already use.

```sh
curl -fsSL https://sh.moul.io/agents | sh -s -- alice bob        # other accounts
curl -fsSL https://sh.moul.io/agents | TS=0 sh                   # skip the tailnet
curl -fsSL https://sh.moul.io/agents | AGENT_KEY="ssh-ed25519 AAAA... ctl" sh
```

The key endpoints are read **once** and written to disk. They are mutable lists controlled
by those accounts, so a machine that re-read them would hand a shell to whoever controls an
account tomorrow. Snapshot, not subscription. They also arrive with their comments stripped,
so every key is anonymous: taking the list takes all of them.

## Everything else

```sh
curl -fsSL https://sh.moul.io | sh                        # the list
curl -fsSL https://sh.moul.io | sh -s -- <sub> [args]     # run one
curl -fsSL https://sh.moul.io | DRY=1 sh -s -- <sub>      # print what it would do
```

| | |
|---|---|
| `agents` | the one above |
| `authorized_keys [ACCOUNTS...]` | add `github.com/<account>.keys`, skipping keys already there |
| `install_tools [PKGS...]` | tmux, htop, git, curl, wget, mosh, jq, ripgrep, through whichever package manager exists |
| `install_brew` | the package manager, macOS or Linux |
| `install_docker` | via get.docker.com |
| `install_go [VERSION]` | the current release by default, with the right architecture |
| `info` | what this machine is |
| `docker_prune` | reclaim docker disk |
| `disk_placeholder [SIZE]` | a file to delete when the disk fills up at 3am |

**`DRY=1` works everywhere.** Every mutating command goes through one wrapper, so a dry run
prints the whole plan and changes nothing. Worth doing once on a machine you care about.

## Reading before running

This is a shell script from the internet that installs software. It is served as
`text/plain` so a browser shows it rather than downloading it, and every published file
carries the commit it was built from, printed by `info` and at the end of `agents`. If
something behaves unlike the source, compare that stamp: a CDN can serve an older copy for
up to a minute after a deploy.

## Working on it

```sh
make test     # everything that needs no network
make test-net # the endpoints this points at are still alive
make run      # what a visitor sees
make serve    # preview the built site on localhost:8000
```

Adding a subcommand is two things: a line in the `SUBCOMMANDS` table and a `sub_<name>()`
function. A test asserts those two agree in both directions, so neither can rot alone.
Mutating commands go through `run`, or `DRY=1` starts lying.

## What CI checks

A script that other machines pipe into a shell deserves more than a syntax check. Every
pull request runs:

| | |
|---|---|
| **shellcheck**, warnings as errors | plus a style pass that reports and never blocks |
| **checkbashisms** | these files claim to be POSIX `sh`; this checks the claim |
| **a danger lint** | no URL piped into a shell, no fixed temp paths, no plain http, no unbounded fetch, no `eval`, no `rm -rf` on a bare variable, plus formatting |
| **five shells** | `sh`, `dash`, `bash`, `zsh` and busybox `ash`, because `\| sh` resolves to whatever that machine has |
| **two systems** | Linux and macOS, where bash is 3.2 and the core utilities are BSD |
| **four distributions** | Alpine, Debian, Fedora and Ubuntu, in containers, as root, the way a fresh server is |
| **real installs** | `install_tools` actually installs, in a throwaway container, on apt, apk and dnf |
| **the bootstrap end to end** | run for real with the tailnet off, then the file it wrote is checked |
| **serving** | build, serve, fetch over http, compare with what was built, and run what came back |
| **idempotency** | four runs leave one copy of each key, and an existing file survives |
| **netlify.toml** | plain text, nosniff, and a cache no longer than five minutes |
| **gitleaks and actionlint** | no secrets, and these workflows are themselves valid |
| **weekly** | the endpoints this repo sends people to still exist, including a Go build for every architecture |

That matrix is not decoration. Writing it found a bug the previous version had for years:
`nc -z` does not exist in busybox, so the check for a running ssh server reported "no ssh
here" on Alpine and every minimal image. It also found that `sudo` was assumed to exist,
which it does not in a root shell on a fresh server, the oldest use case this repo has.

A formatter was considered and rejected: the ones available expand compact one-line guards
into four lines each, which makes a file people have to read before running longer without
making it clearer. The formatting rules that matter are enforced by the danger lint.

## How it is served

Netlify builds `public/` with `bin/build.sh`: each script is stamped with the commit and
published under both a clean path (`/agents`) and its real name (`/agents.sh`), with
`/index.html` for the root. Headers set `text/plain`, `nosniff`, and a **60 second** cache,
because the value of these URLs is that a fix reaches the next machine immediately.

`agents` is the rendered copy of a generic bootstrap kit: the accounts are filled in here,
the logic is maintained upstream.
