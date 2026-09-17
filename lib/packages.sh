#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

BASE_PACKAGES=(git curl wget build-essential htop ripgrep jq tmux zsh)

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

set_default_shell() {
  local zsh_path
  zsh_path="$(command -v zsh)"
  local current_shell
  current_shell="$(getent passwd "$(whoami)" | cut -d: -f7)"

  if [ "$current_shell" == "$zsh_path" ]; then
    log "Default shell is already zsh, skipping"
    return 0
  fi

  log "Setting default shell to zsh ($zsh_path)"
  sudo usermod -s "$zsh_path" "$(whoami)"
  log "Default shell changed to zsh — log out and back in for this to take effect"
}

install_all_packages() {
  install_base_packages
  set_default_shell
  install_oh_my_zsh
  install_nvm
  install_sdkman
  install_docker
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  install_all_packages
fi
