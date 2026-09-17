# linux-setup

Idempotent setup script for a fresh Ubuntu/Debian desktop. Installs
CLI/dev tooling, syncs dotfiles from `github.com/GlynL/dotfiles`, and
provisions an SSH key. Safe to re-run at any time.

## Usage

```bash
git clone <this-repo-url> ~/linux-setup
cd ~/linux-setup
bash setup.sh
```

Run a single module on its own (e.g. after adding a new package to
`lib/packages.sh`):

```bash
bash lib/packages.sh
bash lib/dotfiles.sh
bash lib/ssh.sh
```

## What it does

1. **`lib/packages.sh`** — installs git, curl, wget, build-essential,
   htop, ripgrep, fzf, jq, tmux, zsh, oh-my-zsh, nvm, sdkman, and
   Docker (via Docker's official apt repo); sets zsh as the default
   login shell if it isn't already (idempotent; log out/in required).
2. **`lib/dotfiles.sh`** — clones/pulls `github.com/GlynL/dotfiles`
   into `~/dotfiles`, symlinks `.zshrc` and `.tmux.conf` into `$HOME`
   (backing up any pre-existing real file first), and creates an
   empty `~/.zshrc.local` if missing.
3. **`lib/ssh.sh`** — generates an `ed25519` SSH keypair at
   `~/.ssh/id_ed25519` if one doesn't already exist.

## Secrets

`~/.zshrc.local` is intended to be sourced from the end of `.zshrc`,
but that source line lives in the tracked `.zshrc` itself (a manual,
one-time edit to the `GlynL/dotfiles` repo, outside this codebase) —
it is not something `lib/dotfiles.sh` adds. If the tracked `.zshrc`
doesn't yet contain a `zshrc.local` source line, `.zshrc.local` is
created but nothing reads it, and `lib/dotfiles.sh` will log a
warning to that effect. `.zshrc.local` itself is never part of the
`GlynL/dotfiles` repo and never touched by `git pull`. Once the
source line is in place, put machine-local secrets (API tokens, etc.)
in `.zshrc.local`, not in tracked dotfiles.

## Testing

```bash
bash tests/test_common.sh
bash tests/test_ssh.sh
bash tests/test_dotfiles.sh
bash tests/test_setup.sh
```

`lib/packages.sh` has no automated test (it mutates real system
package state) — verify it manually in a disposable container per
the design doc under `docs/superpowers/specs/`.
