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

# Fix: refuse to run as root/sudo, before any module runs.
# require_not_root() shells out to `id -u` (rather than reading bash's
# readonly $EUID), so it can be tested by putting a fake `id` executable
# earlier on PATH for the duration of the sub-invocation, without any
# env var that a real `sudo bash setup.sh` invocation might accidentally
# have set (which would otherwise defeat the guard).
tmp_project_root=$(mktemp -d)
mkdir -p "$tmp_project_root/lib"
cp "$SCRIPT_DIR/lib/common.sh" "$tmp_project_root/lib/common.sh"
for m in packages dotfiles ssh; do
  cat > "$tmp_project_root/lib/$m.sh" <<EOF
#!/usr/bin/env bash
echo "fake $m module running"
exit 0
EOF
done
chmod +x "$tmp_project_root"/lib/*.sh

sed "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$tmp_project_root\"|" "$SCRIPT_DIR/setup.sh" > "$tmp_project_root/setup.sh"
chmod +x "$tmp_project_root/setup.sh"

fake_id_dir=$(mktemp -d)
cat > "$fake_id_dir/id" <<'EOF'
#!/usr/bin/env bash
echo 0
EOF
chmod +x "$fake_id_dir/id"

set +e
root_output=$(PATH="$fake_id_dir:$PATH" bash "$tmp_project_root/setup.sh" 2>&1)
root_exit_code=$?
set -e

rm -rf "$fake_id_dir"

if [ "$root_exit_code" -ne 0 ] \
  && echo "$root_output" | grep -qi "do not run setup.sh as root" \
  && ! echo "$root_output" | grep -q "fake packages module running"; then
  echo "PASS: refuses to run as root, before any module runs"
else
  echo "FAIL: refuses to run as root, before any module runs"; fail=1
fi

set +e
nonroot_output=$(bash "$tmp_project_root/setup.sh" 2>&1)
nonroot_exit_code=$?
set -e

if [ "$nonroot_exit_code" -eq 0 ] && echo "$nonroot_output" | grep -q "fake packages module running"; then
  echo "PASS: runs normally when not root"
else
  echo "FAIL: runs normally when not root"; fail=1
fi

rm -rf "$tmp_project_root"

rm -rf "$tmp_project"
exit $fail
