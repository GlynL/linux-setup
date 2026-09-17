#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_not_root() {
  if [ "$(id -u)" -eq 0 ]; then
    log "ERROR: do not run setup.sh as root or with sudo. Modules call sudo themselves when they need elevated privileges; running the whole script as root would put dotfiles, the SSH key, oh-my-zsh, nvm, and sdkman under /root instead of your real home directory, and would add root (not you) to the docker group."
    exit 1
  fi
}

require_not_root

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
