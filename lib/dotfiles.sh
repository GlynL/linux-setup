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
    if [ -e "$DOTFILES_DIR" ] && [ -n "$(ls -A "$DOTFILES_DIR" 2>/dev/null)" ]; then
      log "ERROR: $DOTFILES_DIR exists but is not a git repo — move it aside and re-run"
      exit 1
    fi
    log "Cloning dotfiles repo into $DOTFILES_DIR"
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
  fi
}

link_dotfiles() {
  local file target
  for file in "${DOTFILES_FILES[@]}"; do
    target="$HOME/$file"
    if [ ! -e "$DOTFILES_DIR/$file" ]; then
      log "WARNING: $DOTFILES_DIR/$file does not exist, skipping link for $target"
      continue
    fi
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
  if [ -f "$DOTFILES_DIR/.zshrc" ] && ! grep -q "zshrc.local" "$DOTFILES_DIR/.zshrc"; then
    log "WARNING: $DOTFILES_DIR/.zshrc does not source .zshrc.local yet — secrets placed in $local_rc will not load until the tracked .zshrc adds a source line for it"
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
