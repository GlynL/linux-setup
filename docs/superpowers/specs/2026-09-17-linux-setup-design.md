# Fresh Linux Setup Script — Design

**Date:** 2026-09-17
**Status:** Approved, pending implementation plan

## Purpose

A repeatable, idempotent script to provision a fresh Ubuntu/Debian
desktop/workstation with the CLI/dev tooling, dotfiles, and SSH keys
the user needs, without re-doing manual setup steps by hand every time
they get a new machine or reinstall.

## Scope (v1)

In scope:
- Debian/Ubuntu (apt-based) desktop/workstation
- CLI + dev tooling install
- Dotfiles sync from an existing git repo (`GlynL/dotfiles`)
- SSH keypair check/generate

Explicitly out of scope for v1 (deferred, not forgotten):
- GUI applications (browser, terminal emulator, IDE, fonts)
- Other system tweaks (UFW firewall, timezone, hostname)

## Security note (context for this design)

While comparing the user's local `~/dotfiles/.zshrc` against the
`GlynL/dotfiles` repo, a live-looking GitHub Personal Access Token was
found hardcoded in the local file
(`export GITHUB_PERSONAL_ACCESS_TOKEN=ghp_...`). The user was notified
directly and asked to revoke/rotate it independently of this project.
This design assumes that token is no longer valid, and either way
never places any secret into a file that gets pushed to the
`GlynL/dotfiles` repo. See `dotfiles.sh` below.

## Architecture

```
~/linux-setup/
├── setup.sh              # orchestrator: parses flags, runs each module in order
├── lib/
│   ├── common.sh         # shared helpers: log(), is_installed(), backup_file()
│   ├── packages.sh       # apt + third-party CLI/dev tool installs (idempotent)
│   ├── dotfiles.sh       # clone/pull GlynL/dotfiles, symlink files, set up .zshrc.local
│   └── ssh.sh            # check/generate ed25519 SSH keypair
└── README.md
```

`setup.sh` sources `lib/common.sh`, then runs `packages.sh` →
`dotfiles.sh` → `ssh.sh` in order. Each module is also directly
runnable on its own (`bash lib/dotfiles.sh`) for re-running or
debugging a single piece without repeating the whole setup.

## Components

### common.sh

Shared helpers used by every other module:
- `log(msg)` — prefixed, timestamped output so it's clear which module/step is running
- `is_installed(cmd)` — wraps `command -v` for command-based checks
- `apt_installed(pkg)` — wraps `dpkg -s` for package-based checks
- `backup_file(path)` — if `path` exists and is a real file (not already a symlink to the dotfiles repo), moves it to `path.bak.<timestamp>` before it gets overwritten/symlinked

### packages.sh

Idempotent installs, in this order:
1. `apt update` (once, at the top of this module only)
2. Base apt packages, install any that are missing in a single
   `apt install -y` call: `git curl wget build-essential htop ripgrep
   fzf jq tmux neovim zsh`
3. **oh-my-zsh** — skip if `~/.oh-my-zsh` exists, else run its official
   unattended install script
4. **nvm** — skip if `~/.nvm` exists, else run nvm's official install
   script
5. **sdkman** — skip if `~/.sdkman` exists, else run sdkman's official
   install script
6. **Docker (official repo, per docs.docker.com/engine/install/ubuntu)**:
   - Skip the repo/key setup if `/etc/apt/sources.list.d/docker.list`
     already exists
   - Otherwise: add Docker's GPG key to `/etc/apt/keyrings/`, add the
     Docker apt source, `apt update` again
   - Install `docker-ce docker-ce-cli containerd.io
     docker-buildx-plugin docker-compose-plugin` (skip individually if
     already installed)
   - Add the invoking user to the `docker` group if not already a
     member (requires a new login/shell to take effect — script prints
     a reminder, does not force a logout)

### dotfiles.sh

1. If `~/dotfiles` doesn't exist, `git clone github.com/GlynL/dotfiles
   ~/dotfiles`; if it does exist, `git -C ~/dotfiles pull`
2. Before first use, the repo's `.zshrc` is updated (as a one-time
   manual step, see "Repo update" below) to strip the
   `GITHUB_PERSONAL_ACCESS_TOKEN` line and instead end with:
   ```
   [ -f ~/.zshrc.local ] && source ~/.zshrc.local
   ```
3. For each tracked file (`.zshrc`, `.tmux.conf`):
   - If a real file (not a symlink) already exists at the target path
     in `$HOME`, back it up via `backup_file()`
   - Symlink `~/dotfiles/<file>` → `~/<file>`
4. If `~/.zshrc.local` does not exist, create it (`touch`, `chmod
   600`). This file is never part of the git repo and never touched
   by `git pull` — it's local-only. The script does not populate it
   with the actual token value; that's a manual one-time step for the
   user (see below), since the script itself shouldn't be the thing
   handling a live secret value.

**Repo update (one-time, done before/outside the routine script
run):** the `GlynL/dotfiles` repo's `.zshrc` gets replaced with the
user's current local version, minus the `GITHUB_PERSONAL_ACCESS_TOKEN`
line, plus the `~/.zshrc.local` source line appended. This is a single
manual commit+push the user does (or asks for help with) once, not
logic baked into `setup.sh` — `setup.sh` only ever pulls, never
pushes, so re-running it can't accidentally push local secrets or
diverge the remote.

### ssh.sh

- If `~/.ssh/id_ed25519` does not exist: run `ssh-keygen -t ed25519 -C
  "<user>@<host>" -f ~/.ssh/id_ed25519 -N ""` and print the resulting
  public key to stdout
- If it already exists: skip, log that it found an existing key
- Adding the key to GitHub/GitLab remains a manual step — the script
  does not call any git-hosting API

## Data flow

`setup.sh` has no external inputs beyond optional CLI flags (e.g.
`--skip-docker`, deferred until actually needed — v1 takes no flags
and just runs everything). Each module writes to the filesystem
(`$HOME`, `/etc/apt/...`) and to stdout/stderr via `log()`. No module
reads from or writes to any network service other than apt mirrors,
GitHub (cloning/pulling the public dotfiles repo), and the official
install scripts for oh-my-zsh/nvm/sdkman/Docker.

## Error handling

- Every file starts with `set -euo pipefail`
- `setup.sh` runs each module in a subshell and checks its exit code;
  if a module fails, `setup.sh` logs the failure clearly and continues
  to the next module rather than aborting the whole run (a failed
  Docker install shouldn't block dotfiles from syncing)
- At the end, `setup.sh` prints a summary of which modules
  succeeded/failed

## Testing / verification

No automated test suite — this script mutates real system state, so
"tests" in the traditional sense don't apply well. Verification plan:
1. Run the full script inside a throwaway Ubuntu container/VM first
2. Run it a second time back-to-back on that same container/VM and
   confirm the second run reports everything as "already
   present/skipped" (proves idempotency)
3. Only then run it on the real machine
