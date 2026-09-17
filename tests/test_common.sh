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
