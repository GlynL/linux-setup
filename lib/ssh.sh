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
