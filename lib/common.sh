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
