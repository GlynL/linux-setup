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
