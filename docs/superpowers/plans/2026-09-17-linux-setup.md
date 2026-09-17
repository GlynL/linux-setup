# Fresh Linux Setup Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a modular, idempotent bash setup script for a fresh Ubuntu/Debian desktop that installs CLI/dev tooling, syncs dotfiles from `GlynL/dotfiles`, and provisions an SSH key.

**Architecture:** `setup.sh` orchestrates three independent, individually-runnable modules under `lib/` (`packages.sh`, `dotfiles.sh`, `ssh.sh`), all sharing helpers from `lib/common.sh`. Each module is idempotent (safe to re-run) and testable in isolation using temp directories / a local fake git remote, so tests never touch the real `$HOME`, real apt state, or the real `GlynL/dotfiles` repo.

**Tech Stack:** bash (`set -euo pipefail`), apt, git, ssh-keygen. No test framework — hand-rolled pass/fail assertions in plain bash (matches the spec's own testing approach; see spec's "Testing / verification" section).

**Spec:** `docs/superpowers/specs/2026-09-17-linux-setup-design.md`

## Global Constraints

- Target OS: Debian/Ubuntu (apt-based) desktop/workstation.
- Every script file starts with `set -euo pipefail`.
- Docker is installed via Docker's official apt repo (`docs.docker.com/engine/install/ubuntu`), not Ubuntu's `docker.io`.
- `dotfiles.sh` must never push to `GlynL/dotfiles` — it only clones/pulls. Any repo update is a separate, explicitly-confirmed manual step (Task 7).
- No secret values (tokens, keys) are ever written into a file that gets committed/pushed to `GlynL/dotfiles`.
- `setup.sh` continues running remaining modules if one module fails, and reports a per-module pass/fail summary at the end.

---

## File Structure

```
~/linux-setup/
├── setup.sh
├── lib/
│   ├── common.sh
│   ├── packages.sh
│   ├── dotfiles.sh
│   └── ssh.sh
├── tests/
│   ├── test_common.sh
│   ├── test_ssh.sh
│   ├── test_dotfiles.sh
│   └── test_setup.sh
└── README.md
```

---

### Task 1: common.sh — shared helpers

**Files:**
- Create: `lib/common.sh`
- Test: `tests/test_common.sh`

**Interfaces:**
- Produces: `log(msg...)`, `is_installed(cmd) -> exit code`, `apt_installed(pkg) -> exit code`, `backup_file(path)` — all consumed by every later task.

- [ ] **Step 1: Write the failing test**

Create `tests/test_common.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

fail=0

if is_installed bash; then echo "PASS: is_installed bash"; else echo "FAIL: is_installed bash"; fail=1; fi

if ! is_installed this_command_does_not_exist_xyz; then echo "PASS: is_installed missing cmd"; else echo "FAIL: is_installed missing cmd"; fail=1; fi

if ! apt_installed this-package-does-not-exist-xyz; then echo "PASS: apt_installed missing pkg"; else echo "FAIL: apt_installed missing pkg"; fail=1; fi

tmpdir=$(mktemp -d)
touch "$tmpdir/foo.txt"
backup_file "$tmpdir/foo.txt"
if [ ! -e "$tmpdir/foo.txt" ] && ls "$tmpdir"/foo.txt.bak.* >/dev/null 2>&1; then
  echo "PASS: backup_file renames real file"
else
  echo "FAIL: backup_file renames real file"; fail=1
fi
rm -rf "$tmpdir"

tmpdir=$(mktemp -d)
touch "$tmpdir/target.txt"
ln -s "$tmpdir/target.txt" "$tmpdir/link.txt"
backup_file "$tmpdir/link.txt"
if [ -L "$tmpdir/link.txt" ]; then
  echo "PASS: backup_file leaves symlink alone"
else
  echo "FAIL: backup_file leaves symlink alone"; fail=1
fi
rm -rf "$tmpdir"

exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_common.sh`
Expected: FAIL — `lib/common.sh: No such file or directory` (source fails, nonzero exit).

- [ ] **Step 3: Write minimal implementation**

Create `lib/common.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

is_installed() {
  command -v "$1" >/dev/null 2>&1
}

apt_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

backup_file() {
  local path="$1"
  if [ -e "$path" ] && [ ! -L "$path" ]; then
    local backup="${path}.bak.$(date +%Y%m%d%H%M%S)"
    mv "$path" "$backup"
    log "Backed up $path -> $backup"
  fi
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_common.sh`
Expected: all lines print `PASS:...`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add lib/common.sh tests/test_common.sh
git commit -m "feat: add common.sh shared helpers (log, is_installed, apt_installed, backup_file)"
```

---

### Task 2: ssh.sh — SSH keypair check/generate

**Files:**
- Create: `lib/ssh.sh`
- Test: `tests/test_ssh.sh`

**Interfaces:**
- Consumes: `log(msg)` from `lib/common.sh`.
- Produces: `ensure_ssh_key()`; when run directly (`bash lib/ssh.sh`), calls `ensure_ssh_key`. Honors `SSH_KEY_PATH` env var override (defaults to `$HOME/.ssh/id_ed25519`), used by tests and by `setup.sh`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_ssh.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail=0
tmpdir=$(mktemp -d)

SSH_KEY_PATH="$tmpdir/id_ed25519" bash "$SCRIPT_DIR/lib/ssh.sh" > /tmp/ssh_test_out_1.txt 2>&1
if [ -f "$tmpdir/id_ed25519" ] && [ -f "$tmpdir/id_ed25519.pub" ]; then
  echo "PASS: generates key when missing"
else
  echo "FAIL: generates key when missing"; fail=1
fi

before_hash=$(sha256sum "$tmpdir/id_ed25519" | awk '{print $1}')
SSH_KEY_PATH="$tmpdir/id_ed25519" bash "$SCRIPT_DIR/lib/ssh.sh" > /tmp/ssh_test_out_2.txt 2>&1
after_hash=$(sha256sum "$tmpdir/id_ed25519" | awk '{print $1}')
if [ "$before_hash" == "$after_hash" ] && grep -q "already exists" /tmp/ssh_test_out_2.txt; then
  echo "PASS: skips existing key on re-run"
else
  echo "FAIL: skips existing key on re-run"; fail=1
fi

rm -rf "$tmpdir" /tmp/ssh_test_out_1.txt /tmp/ssh_test_out_2.txt
exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_ssh.sh`
Expected: FAIL — `lib/ssh.sh: No such file or directory`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/ssh.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"

ensure_ssh_key() {
  if [ -f "$SSH_KEY_PATH" ]; then
    log "SSH key already exists at $SSH_KEY_PATH, skipping"
    return 0
  fi

  mkdir -p "$(dirname "$SSH_KEY_PATH")"
  chmod 700 "$(dirname "$SSH_KEY_PATH")"
  ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)" -f "$SSH_KEY_PATH" -N ""
  log "Generated new SSH key at $SSH_KEY_PATH"
  log "Public key:"
  cat "$SSH_KEY_PATH.pub"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  ensure_ssh_key
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_ssh.sh`
Expected: both lines print `PASS:...`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add lib/ssh.sh tests/test_ssh.sh
git commit -m "feat: add ssh.sh for idempotent ed25519 keypair provisioning"
```

---

### Task 3: dotfiles.sh — sync dotfiles repo and symlink files

**Files:**
- Create: `lib/dotfiles.sh`
- Test: `tests/test_dotfiles.sh`

**Interfaces:**
- Consumes: `log(msg)`, `backup_file(path)` from `lib/common.sh`.
- Produces: `sync_dotfiles_repo()`, `link_dotfiles()`, `ensure_zshrc_local()`, `sync_all_dotfiles()`. When run directly, calls `sync_all_dotfiles`. Honors `DOTFILES_REPO` (default `https://github.com/GlynL/dotfiles.git`) and `DOTFILES_DIR` (default `$HOME/dotfiles`) env var overrides, used by tests and `setup.sh`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_dotfiles.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail=0

remote_dir=$(mktemp -d)
git -C "$remote_dir" init -q -b main
echo "# fake zshrc" > "$remote_dir/.zshrc"
echo "# fake tmux conf" > "$remote_dir/.tmux.conf"
git -C "$remote_dir" add -A
git -C "$remote_dir" -c user.email=test@test.com -c user.name=test commit -q -m "init"

fake_home=$(mktemp -d)
fake_dotfiles_dir="$fake_home/dotfiles"

HOME="$fake_home" DOTFILES_REPO="$remote_dir" DOTFILES_DIR="$fake_dotfiles_dir" \
  bash "$SCRIPT_DIR/lib/dotfiles.sh" > /tmp/dotfiles_test_out_1.txt 2>&1

if [ -L "$fake_home/.zshrc" ] && [ -L "$fake_home/.tmux.conf" ] && [ -f "$fake_home/.zshrc.local" ]; then
  echo "PASS: first run clones, links, and creates .zshrc.local"
else
  echo "FAIL: first run clones, links, and creates .zshrc.local"; fail=1
fi

rm "$fake_home/.zshrc"
echo "an existing real zshrc" > "$fake_home/.zshrc"

HOME="$fake_home" DOTFILES_REPO="$remote_dir" DOTFILES_DIR="$fake_dotfiles_dir" \
  bash "$SCRIPT_DIR/lib/dotfiles.sh" > /tmp/dotfiles_test_out_2.txt 2>&1

if [ -L "$fake_home/.zshrc" ] && ls "$fake_home"/.zshrc.bak.* >/dev/null 2>&1; then
  echo "PASS: existing real file backed up before overwrite"
else
  echo "FAIL: existing real file backed up before overwrite"; fail=1
fi

before_backups=$(ls "$fake_home"/.zshrc.bak.* 2>/dev/null | wc -l)
HOME="$fake_home" DOTFILES_REPO="$remote_dir" DOTFILES_DIR="$fake_dotfiles_dir" \
  bash "$SCRIPT_DIR/lib/dotfiles.sh" > /tmp/dotfiles_test_out_3.txt 2>&1
after_backups=$(ls "$fake_home"/.zshrc.bak.* 2>/dev/null | wc -l)
if [ -L "$fake_home/.zshrc" ] && [ "$before_backups" == "$after_backups" ]; then
  echo "PASS: re-run is idempotent, no extra backups"
else
  echo "FAIL: re-run is idempotent, no extra backups"; fail=1
fi

rm -rf "$remote_dir" "$fake_home" /tmp/dotfiles_test_out_1.txt /tmp/dotfiles_test_out_2.txt /tmp/dotfiles_test_out_3.txt
exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_dotfiles.sh`
Expected: FAIL — `lib/dotfiles.sh: No such file or directory`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/dotfiles.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/GlynL/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
DOTFILES_FILES=(.zshrc .tmux.conf)

sync_dotfiles_repo() {
  if [ -d "$DOTFILES_DIR/.git" ]; then
    log "Dotfiles repo already present at $DOTFILES_DIR, pulling latest"
    git -C "$DOTFILES_DIR" pull --ff-only
  else
    log "Cloning dotfiles repo into $DOTFILES_DIR"
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
  fi
}

link_dotfiles() {
  local file target
  for file in "${DOTFILES_FILES[@]}"; do
    target="$HOME/$file"
    backup_file "$target"
    if [ -L "$target" ]; then
      rm "$target"
    fi
    ln -s "$DOTFILES_DIR/$file" "$target"
    log "Linked $target -> $DOTFILES_DIR/$file"
  done
}

ensure_zshrc_local() {
  local local_rc="$HOME/.zshrc.local"
  if [ ! -f "$local_rc" ]; then
    touch "$local_rc"
    chmod 600 "$local_rc"
    log "Created empty $local_rc (add machine-local secrets/exports here; never committed)"
  fi
}

sync_all_dotfiles() {
  sync_dotfiles_repo
  link_dotfiles
  ensure_zshrc_local
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  sync_all_dotfiles
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_dotfiles.sh`
Expected: all three lines print `PASS:...`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add lib/dotfiles.sh tests/test_dotfiles.sh
git commit -m "feat: add dotfiles.sh to sync GlynL/dotfiles and symlink tracked files"
```

---

### Task 4: packages.sh — apt + third-party CLI/dev tool installs

**Files:**
- Create: `lib/packages.sh`

**Interfaces:**
- Consumes: `log(msg)`, `apt_installed(pkg)` from `lib/common.sh`.
- Produces: `install_base_packages()`, `install_oh_my_zsh()`, `install_nvm()`, `install_sdkman()`, `install_docker()`, `install_all_packages()`. When run directly, calls `install_all_packages`.

This module installs real system packages and third-party tools — it isn't unit-testable against a fake `$HOME` the way Tasks 1-3 are (it needs real apt and real network access, and mutates real system package state). Per the spec's "Testing / verification" section, this module is verified manually in a disposable container rather than with an automated test file.

- [ ] **Step 1: Write the implementation**

Create `lib/packages.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

BASE_PACKAGES=(git curl wget build-essential htop ripgrep fzf jq tmux neovim zsh)

install_base_packages() {
  local missing=()
  local pkg
  for pkg in "${BASE_PACKAGES[@]}"; do
    if ! apt_installed "$pkg"; then
      missing+=("$pkg")
    fi
  done

  if [ ${#missing[@]} -eq 0 ]; then
    log "All base packages already installed, skipping apt install"
    return 0
  fi

  log "Installing missing base packages: ${missing[*]}"
  sudo apt-get update -y
  sudo apt-get install -y "${missing[@]}"
}

install_oh_my_zsh() {
  if [ -d "$HOME/.oh-my-zsh" ]; then
    log "oh-my-zsh already installed, skipping"
    return 0
  fi
  log "Installing oh-my-zsh"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

install_nvm() {
  if [ -d "$HOME/.nvm" ]; then
    log "nvm already installed, skipping"
    return 0
  fi
  log "Installing nvm"
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
}

install_sdkman() {
  if [ -d "$HOME/.sdkman" ]; then
    log "sdkman already installed, skipping"
    return 0
  fi
  log "Installing sdkman"
  curl -s "https://get.sdkman.io" | bash
}

install_docker() {
  if [ -f /etc/apt/sources.list.d/docker.list ]; then
    log "Docker apt repo already configured, skipping repo setup"
  else
    log "Adding Docker's official apt repo"
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    local arch codename
    arch=$(dpkg --print-architecture)
    codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
    echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y
  fi

  local docker_packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
  local missing=()
  local pkg
  for pkg in "${docker_packages[@]}"; do
    if ! apt_installed "$pkg"; then
      missing+=("$pkg")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    log "Installing missing Docker packages: ${missing[*]}"
    sudo apt-get install -y "${missing[@]}"
  else
    log "All Docker packages already installed, skipping"
  fi

  if ! groups "$(whoami)" | grep -q '\bdocker\b'; then
    log "Adding $(whoami) to the docker group (log out/in for this to take effect)"
    sudo usermod -aG docker "$(whoami)"
  else
    log "$(whoami) already in the docker group"
  fi
}

install_all_packages() {
  install_base_packages
  install_oh_my_zsh
  install_nvm
  install_sdkman
  install_docker
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  install_all_packages
fi
```

- [ ] **Step 2: Manually verify in a disposable container**

Run:
```bash
docker run --rm -it -v "$HOME/linux-setup:/setup" ubuntu:24.04 bash -c "apt-get update && apt-get install -y sudo && useradd -m tester && echo 'tester ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && su - tester -c 'bash /setup/lib/packages.sh'"
```
Expected: base packages, oh-my-zsh, nvm, sdkman, and Docker all install without error.

Run the same command again.
Expected: every step logs "already installed, skipping" / "already configured, skipping" — no re-downloads, no errors, confirming idempotency.

- [ ] **Step 3: Commit**

```bash
git add lib/packages.sh
git commit -m "feat: add packages.sh for idempotent CLI/dev tool + Docker installs"
```

---

### Task 5: setup.sh — orchestrator with continue-on-failure and summary

**Files:**
- Create: `setup.sh`
- Test: `tests/test_setup.sh`

**Interfaces:**
- Consumes: `log(msg)` from `lib/common.sh`; runs `lib/packages.sh`, `lib/dotfiles.sh`, `lib/ssh.sh` as subprocesses.
- Produces: exit code 0 if all modules succeed, 1 if any module fails; prints a `<module>: OK` / `<module>: FAILED` line per module.

- [ ] **Step 1: Write the failing test**

Create `tests/test_setup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail=0
tmp_project=$(mktemp -d)
mkdir -p "$tmp_project/lib"
cp "$SCRIPT_DIR/lib/common.sh" "$tmp_project/lib/common.sh"

cat > "$tmp_project/lib/packages.sh" <<'EOF'
#!/usr/bin/env bash
echo "fake packages module running"
exit 1
EOF
cat > "$tmp_project/lib/dotfiles.sh" <<'EOF'
#!/usr/bin/env bash
echo "fake dotfiles module running"
exit 0
EOF
cat > "$tmp_project/lib/ssh.sh" <<'EOF'
#!/usr/bin/env bash
echo "fake ssh module running"
exit 0
EOF
chmod +x "$tmp_project"/lib/*.sh

sed "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$tmp_project\"|" "$SCRIPT_DIR/setup.sh" > "$tmp_project/setup.sh"
chmod +x "$tmp_project/setup.sh"

set +e
output=$(bash "$tmp_project/setup.sh" 2>&1)
exit_code=$?
set -e

if echo "$output" | grep -q "fake packages module running" \
  && echo "$output" | grep -q "fake dotfiles module running" \
  && echo "$output" | grep -q "fake ssh module running"; then
  echo "PASS: all modules run even after one fails"
else
  echo "FAIL: all modules run even after one fails"; fail=1
fi

if echo "$output" | grep -q "packages: FAILED" \
  && echo "$output" | grep -q "dotfiles: OK" \
  && echo "$output" | grep -q "ssh: OK"; then
  echo "PASS: summary reports correct status per module"
else
  echo "FAIL: summary reports correct status per module"; fail=1
fi

if [ "$exit_code" -ne 0 ]; then
  echo "PASS: overall exit code is non-zero when a module fails"
else
  echo "FAIL: overall exit code is non-zero when a module fails"; fail=1
fi

rm -rf "$tmp_project"
exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_setup.sh`
Expected: FAIL — `setup.sh: No such file or directory`.

- [ ] **Step 3: Write minimal implementation**

Create `setup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

MODULES=(packages dotfiles ssh)
declare -A RESULTS

for module in "${MODULES[@]}"; do
  log "=== Running module: $module ==="
  if bash "$SCRIPT_DIR/lib/$module.sh"; then
    RESULTS[$module]="OK"
  else
    RESULTS[$module]="FAILED"
    log "Module $module failed, continuing with remaining modules"
  fi
done

log "=== Setup summary ==="
overall=0
for module in "${MODULES[@]}"; do
  log "$module: ${RESULTS[$module]}"
  if [ "${RESULTS[$module]}" == "FAILED" ]; then
    overall=1
  fi
done

exit $overall
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_setup.sh`
Expected: all three lines print `PASS:...`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add setup.sh tests/test_setup.sh
git commit -m "feat: add setup.sh orchestrator with continue-on-failure and summary"
```

---

### Task 6: README.md — usage documentation

**Files:**
- Create: `README.md`

**Interfaces:**
- None (documentation only).

- [ ] **Step 1: Write README.md**

Create `README.md`:

```markdown
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
   htop, ripgrep, fzf, jq, tmux, neovim, zsh, oh-my-zsh, nvm, sdkman,
   and Docker (via Docker's official apt repo).
2. **`lib/dotfiles.sh`** — clones/pulls `github.com/GlynL/dotfiles`
   into `~/dotfiles`, symlinks `.zshrc` and `.tmux.conf` into `$HOME`
   (backing up any pre-existing real file first), and creates an
   empty `~/.zshrc.local` if missing.
3. **`lib/ssh.sh`** — generates an `ed25519` SSH keypair at
   `~/.ssh/id_ed25519` if one doesn't already exist.

## Secrets

`~/.zshrc.local` is sourced from the end of `.zshrc` but is never part
of the `GlynL/dotfiles` repo and never touched by `git pull`. Put
machine-local secrets (API tokens, etc.) there, not in tracked
dotfiles.

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
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with usage, module breakdown, and secrets handling"
```

---

### Task 7: Update `GlynL/dotfiles` repo `.zshrc` (one-time, manual, requires explicit confirmation before push)

This task is different from Tasks 1-6: it modifies and pushes to the
**real, existing** `GlynL/dotfiles` GitHub repo, which `dotfiles.sh`
will clone/pull from once this is live. This is a hard-to-reverse,
externally-visible action (a push to a repo other tooling and other
clones will pull) — do not run the push step without the user
explicitly confirming it first, separately from approval of this plan
as a whole.

**Files (in a separate clone of `GlynL/dotfiles`, not this repo):**
- Modify: `.zshrc`

- [ ] **Step 1: Clone the dotfiles repo to a scratch location**

```bash
git clone https://github.com/GlynL/dotfiles.git /tmp/dotfiles-update
```

- [ ] **Step 2: Replace `.zshrc` with the current local version, minus the token**

Copy `~/dotfiles/.zshrc` (the user's current local file) over
`/tmp/dotfiles-update/.zshrc`, then remove the line:
```
export GITHUB_PERSONAL_ACCESS_TOKEN=ghp_...
```
and append this line at the end of the file if not already present:
```
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
```

- [ ] **Step 3: Review the diff**

```bash
cd /tmp/dotfiles-update && git diff
```
Confirm: no token or other secret value appears anywhere in the diff.

- [ ] **Step 4: Ask the user to explicitly confirm the push**

Show the diff and ask: "This will push the updated `.zshrc` to the
public `GlynL/dotfiles` repo on GitHub. Confirm?" Do not proceed to
Step 5 without an explicit yes.

- [ ] **Step 5: Commit and push (only after confirmation)**

```bash
cd /tmp/dotfiles-update
git add .zshrc
git commit -m "Update .zshrc, move secrets to untracked .zshrc.local"
git push origin main
```

- [ ] **Step 6: Clean up scratch clone**

```bash
rm -rf /tmp/dotfiles-update
```

---

## Self-Review Notes

- **Spec coverage:** common.sh (Task 1) ✓, packages.sh incl. Docker official-repo install (Task 4) ✓, dotfiles.sh incl. `.zshrc.local` and backup-before-overwrite (Task 3) ✓, ssh.sh (Task 2) ✓, setup.sh continue-on-failure + summary (Task 5) ✓, README (Task 6) ✓, one-time repo secret cleanup (Task 7) ✓. GUI apps and other system tweaks are explicitly out of scope per spec — no task needed.
- **Placeholder scan:** no TBD/TODO; every step has real code or an exact command with expected output.
- **Type/interface consistency:** `log`, `is_installed`, `apt_installed`, `backup_file` (Task 1) are used with matching names/signatures in Tasks 2-5. `DOTFILES_REPO`/`DOTFILES_DIR`/`SSH_KEY_PATH` env var names are consistent between each module's implementation and its test. `MODULES=(packages dotfiles ssh)` in Task 5 matches the three module filenames from Tasks 2-4.
