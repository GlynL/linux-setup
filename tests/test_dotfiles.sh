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

# Fix: a tracked file missing from the dotfiles repo (e.g. DOTFILES_FILES
# drifted from what's actually in the repo) must warn and skip that one
# file, not create a dangling symlink and not touch any pre-existing real
# file for that name.
missing_file_remote=$(mktemp -d)
git -C "$missing_file_remote" init -q -b main
echo "# fake zshrc" > "$missing_file_remote/.zshrc"
# deliberately no .tmux.conf in this repo
git -C "$missing_file_remote" add -A
git -C "$missing_file_remote" -c user.email=test@test.com -c user.name=test commit -q -m "init"

missing_file_home=$(mktemp -d)
echo "pre-existing real tmux conf" > "$missing_file_home/.tmux.conf"

HOME="$missing_file_home" DOTFILES_REPO="$missing_file_remote" DOTFILES_DIR="$missing_file_home/dotfiles" \
  bash "$SCRIPT_DIR/lib/dotfiles.sh" > /tmp/dotfiles_test_out_4.txt 2>&1

if [ -L "$missing_file_home/.zshrc" ] \
  && [ -f "$missing_file_home/.tmux.conf" ] \
  && [ ! -L "$missing_file_home/.tmux.conf" ] \
  && grep -q "pre-existing real tmux conf" "$missing_file_home/.tmux.conf" \
  && grep -qi "warning" /tmp/dotfiles_test_out_4.txt; then
  echo "PASS: missing tracked file warns and skips instead of creating a dangling symlink"
else
  echo "FAIL: missing tracked file warns and skips instead of creating a dangling symlink"; fail=1
fi

rm -rf "$missing_file_remote" "$missing_file_home" /tmp/dotfiles_test_out_4.txt

# Fix: DOTFILES_DIR exists as a non-empty, non-git directory (e.g. a
# partial clone from a previous run, or a plain directory that predates
# this tooling) must fail with a clear, actionable error instead of git's
# raw fatal message.
nongit_home=$(mktemp -d)
nongit_dotfiles_dir="$nongit_home/dotfiles"
mkdir -p "$nongit_dotfiles_dir"
echo "pre-existing plain file" > "$nongit_dotfiles_dir/somefile.txt"

set +e
HOME="$nongit_home" DOTFILES_REPO="$remote_dir" DOTFILES_DIR="$nongit_dotfiles_dir" \
  bash "$SCRIPT_DIR/lib/dotfiles.sh" > /tmp/dotfiles_test_out_5.txt 2>&1
nongit_exit=$?
set -e

if [ "$nongit_exit" -ne 0 ] && grep -qi "not a git repo" /tmp/dotfiles_test_out_5.txt; then
  echo "PASS: non-git non-empty DOTFILES_DIR fails with a clear error"
else
  echo "FAIL: non-git non-empty DOTFILES_DIR fails with a clear error"; fail=1
fi

rm -rf "$nongit_home" /tmp/dotfiles_test_out_5.txt

# Fix: warn when the tracked .zshrc doesn't source .zshrc.local yet, so a
# secret placed there silently doesn't load.
nosource_remote=$(mktemp -d)
git -C "$nosource_remote" init -q -b main
echo "# fake zshrc with no local-secrets source line" > "$nosource_remote/.zshrc"
echo "# fake tmux conf" > "$nosource_remote/.tmux.conf"
git -C "$nosource_remote" add -A
git -C "$nosource_remote" -c user.email=test@test.com -c user.name=test commit -q -m "init"

nosource_home=$(mktemp -d)
HOME="$nosource_home" DOTFILES_REPO="$nosource_remote" DOTFILES_DIR="$nosource_home/dotfiles" \
  bash "$SCRIPT_DIR/lib/dotfiles.sh" > /tmp/dotfiles_test_out_6.txt 2>&1

if grep -qi "warning" /tmp/dotfiles_test_out_6.txt && grep -q "zshrc.local" /tmp/dotfiles_test_out_6.txt; then
  echo "PASS: warns when tracked .zshrc does not source .zshrc.local"
else
  echo "FAIL: warns when tracked .zshrc does not source .zshrc.local"; fail=1
fi

rm -rf "$nosource_remote" "$nosource_home" /tmp/dotfiles_test_out_6.txt

rm -rf "$remote_dir" "$fake_home" /tmp/dotfiles_test_out_1.txt /tmp/dotfiles_test_out_2.txt /tmp/dotfiles_test_out_3.txt
exit $fail
