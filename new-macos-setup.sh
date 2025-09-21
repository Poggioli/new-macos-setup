#!/bin/bash
set -e

# --- Request sudo once at the beginning ---
sudo -v
# Keep-alive: update existing sudo timestamp until script finishes
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# --- Helper Functions ---
append_block_if_not_exists() {
  local BEGIN="$1"
  local END="$2"
  local FILE="$3"
  shift 3
  local LINES=("$@")

  if ! grep -q "$BEGIN" "$FILE"; then
    echo "" >> "$FILE"
    echo "$BEGIN" >> "$FILE"
    for LINE in "${LINES[@]}"; do
      echo "$LINE" >> "$FILE"
    done
    echo "$END" >> "$FILE"
  fi
}

backup_zshrc() {
  if [ -f "$HOME/.zshrc" ]; then
    read -rp "Do you want to backup your current .zshrc before cleaning? [Y/n]: " ANSWER
    ANSWER=${ANSWER:-Y}
    if [[ "$ANSWER" =~ ^[Yy]$ ]]; then
      local TIMESTAMP
      TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
      cp "$HOME/.zshrc" "$HOME/.zshrc.backup_$TIMESTAMP"
      echo "💾 Original .zshrc backed up to .zshrc.backup_$TIMESTAMP"
    fi
    echo "🧹 Cleaning existing .zshrc..."
    > "$HOME/.zshrc"
  fi
}

# --- Homebrew Installation ---
install_homebrew() {
  echo "Checking if Homebrew is already installed..."
  touch ~/.zprofile ~/.zshrc

  if command -v brew >/dev/null 2>&1; then
    echo "✅ Homebrew is already installed at $(which brew)"
    return
  fi

  echo ""
  echo "⬇️ Installing Homebrew..."
  local arch_name="$(uname -m)"

  if [ "$arch_name" = "arm64" ]; then
    echo "Detected Apple Silicon (arm64)"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    append_block_if_not_exists "#### BEGIN HOMEBREW ARM ####" "#### END HOMEBREW ARM ####" ~/.zprofile \
      'eval "$(/opt/homebrew/bin/brew shellenv)"'
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    echo "Detected Intel (x86_64)"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    append_block_if_not_exists "#### BEGIN HOMEBREW INTEL ####" "#### END HOMEBREW INTEL ####" ~/.zprofile \
      'eval "$(/usr/local/bin/brew shellenv)"'
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  echo "✅ Homebrew installed successfully"
  brew update
  brew doctor
}

# --- App Installation ---
install_apps() {
  echo ""
  echo "⬇️ Installing Google Chrome..."
  brew install --cask google-chrome
  echo "✅ Google Chrome installed successfully!"

  echo ""
  echo "⬇️ Installing VS Code..."
  brew install --cask visual-studio-code
  echo "✅ VS Code installed successfully!"

  echo ""
  echo "⬇️ Installing Docker CLI..."
  brew install docker
  docker run hello-world || true
  echo "✅ Docker CLI installed successfully!"

  echo ""
  echo "⬇️ Installing Docker Compose..."
  brew install docker-compose
  docker-compose -v
  echo "✅ Docker Compose installed successfully!"
}

# --- Podman Installation & Configuration ---
install_podman() {
  echo ""
  echo "⬇️ Installing Podman..."
  brew install podman
  echo "✅ Podman installed successfully!"

  echo ""
  echo "🔧 Configuring Podman"

  if podman machine list --format "{{.Name}}" | grep -q "podman-machine-default"; then
    echo "🛑 Stopping existing Podman machine..."
    podman machine stop || true
  fi

  podman machine init || true
  podman machine set --rootful
  podman machine start || true
  podman machine list
  podman run --rm hello-world || true
  echo "✅ Podman configured successfully!"

  echo ""
  echo "⬇️ Installing Podman Mac Helper..."
  sudo /opt/homebrew/bin/podman-mac-helper install

  append_block_if_not_exists "#### BEGIN PODMAN ####" "#### END PODMAN ####" ~/.zshrc \
    'export PATH="/opt/homebrew/bin:$PATH"' \
    'export DOCKER_HOST="unix:///var/folders/rm/4658q9zd1_q0_5_dv5j3r1m80000gn/T/podman/podman-machine-default-api.sock"'

  echo "✅ Podman Mac Helper configured successfully!"

  echo ""
  echo "⬇️ Installing Podman Desktop..."
  brew install --cask podman-desktop
  echo "✅ Podman Desktop installed successfully!"
}

# --- NVM and Node Installation ---
install_nvm_node() {
  echo ""
  echo "⬇️ Installing NVM..."
  brew install nvm
  mkdir -p ~/.nvm
  export NVM_DIR="$HOME/.nvm"
  [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"
  [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"
  echo "✅ NVM installed successfully!"

  echo ""
  echo "🔧 Configuring NVM and Node in zshrc"
  append_block_if_not_exists "#### BEGIN NVM ####" "#### END NVM ####" ~/.zshrc \
    'export NVM_DIR="$HOME/.nvm"' \
    '[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"' \
    '[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"' \
    '' \
    'autoload -U add-zsh-hook' \
    'load-nvmrc() {' \
    '  local node_version="$(nvm version)"' \
    '  local nvmrc_path="$(nvm_find_nvmrc)"' \
    '  if [ -n "$nvmrc_path" ]; then' \
    '    local nvmrc_node_version=$(nvm version "$(cat "${nvmrc_path}")")' \
    '    if [ "$nvmrc_node_version" = "N/A" ]; then' \
    '      nvm install' \
    '    elif [ "$nvmrc_node_version" != "$node_version" ]; then' \
    '      nvm use' \
    '    fi' \
    '  elif [ "$node_version" != "$(nvm version default)" ]; then' \
    '    echo "Reverting to nvm default version"' \
    '    nvm use default' \
    '  fi' \
    '  corepack enable' \
    '  corepack prepare yarn@stable --activate' \
    '}' \
    'add-zsh-hook chpwd load-nvmrc' \
    'load-nvmrc'

  echo ""
  echo "⬇️ Installing Node LTS..."
  nvm install --lts
  corepack enable
  corepack prepare yarn@stable --activate
  echo "✅ Node LTS installed successfully!"

  append_block_if_not_exists "#### BEGIN NPMRC ####" "#### END NPMRC ####" ~/.npmrc \
    'registry=https://registry.npmjs.org/'
}

# --- Install autoenv ---
install_auto_env() {
  echo ""
  echo "⬇️ Installing Autoenv..."
  brew install autoenv

  append_block_if_not_exists "#### BEGIN AUTO_ENV ####" "#### END AUTO_ENV ####" ~/.zprofile \
    'eval "$(autoenv_init -)"'

  eval "$(autoenv_init -)"
  echo "✅ Autoenv installed successfully"
}

# --- Oh My Zsh Installation ---
install_ohmyzsh() {
  echo ""
  echo "⬇️ Installing zsh and Oh My Zsh..."
  brew install zsh

  if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "🗑️ Removing existing Oh My Zsh installation..."
    rm -rf "$HOME/.oh-my-zsh"
  fi

  # Install Oh My Zsh without touching .zshrc
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes ZSH="$HOME/.oh-my-zsh" \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  echo "✅ Zsh & Oh My Zsh installed successfully!"

  echo ""
  echo "🔧 Adding custom Oh My Zsh configuration to zshrc (safe append)"
  append_block_if_not_exists "#### BEGIN OH-MY-ZSH ####" "#### END OH-MY-ZSH ####" ~/.zshrc \
    '# If you come from bash you might have to change your $PATH.' \
    '# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH' \
    'export ZSH="$HOME/.oh-my-zsh"' \
    'ZSH_THEME="robbyrussell"' \
    'CASE_SENSITIVE="true"' \
    'zstyle ":omz:update" mode reminder' \
    'export ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"' \
    'plugins=(git extract docker docker-compose zsh-autosuggestions zsh-syntax-highlighting sudo dirhistory history)' \
    'source $ZSH/oh-my-zsh.sh'
}

# --- Oh My Zsh Plugins Installation ---
install_ohmyzsh_plugins() {
  echo ""
  echo "⬇️ Cloning Oh My Zsh plugins..."
  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  mkdir -p "$ZSH_CUSTOM/plugins"

  # Clone zsh-autosuggestions if missing
  if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    echo ""
    echo "⬇️ Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  fi

  # Clone zsh-syntax-highlighting if missing
  if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    echo ""
    echo "⬇️ Installing zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  fi

  echo "✅ Oh My Zsh plugins installed successfully!"
}

# --- Customize RobbyRussell Theme ---
customize_theme() {
  echo ""
  echo "🔧 Customizing RobbyRussell theme..."
  mkdir -p "$ZSH_CUSTOM/themes"
  cp "$ZSH/themes/robbyrussell.zsh-theme" "$ZSH_CUSTOM/themes/"
  sed -i '' 's/%c/%~/' "$ZSH_CUSTOM/themes/robbyrussell.zsh-theme"

  append_block_if_not_exists "#### BEGIN ROBBYRUSSELL THEME ####" "#### END ROBBYRUSSELL THEME ####" ~/.zshrc \
    "export ZSH_THEME=\"$ZSH_CUSTOM/themes/robbyrussell.zsh-theme\"" \
    "PROMPT='%{\$fg[cyan]%}%~%{\$reset_color%} \$(git_prompt_info)'"
}

# --- Main Execution ---
main() {
  backup_zshrc
  install_homebrew
  install_auto_env
  install_podman
  install_apps
  install_nvm_node
  install_ohmyzsh
  install_ohmyzsh_plugins
  customize_theme

  echo ""

cat <<'EOF'
  /\/\      _    _ _       _                  _   ____  _             _   _                                           
  >  <     / \  | | |   __| | ___  _ __   ___| | / ___|| |_ __ _ _ __| |_(_)_ __   __ _    __ _   _ __   _____      __
 _\/\ |   / _ \ | | |  / _` |/ _ \| '_ \ / _ \ | \___ \| __/ _` | '__| __| | '_ \ / _` |  / _` | | '_ \ / _ \ \ /\ / /
/ __` |  / ___ \| | | | (_| | (_) | | | |  __/_|  ___) | || (_| | |  | |_| | | | | (_| | | (_| | | | | |  __/\ V  V / 
\____/  /_/   \_\_|_|  \__,_|\___/|_| |_|\___(_) |____/ \__\__,_|_|   \__|_|_| |_|\__, |  \__,_| |_| |_|\___| \_/\_/  
                                                                                  |___/                               
 _____    _                         _               _          _                 _         _ _ 
|__  /___| |__    ___  ___  ___ ___(_) ___  _ __   | |_ ___   | | ___   __ _  __| |   __ _| | |
  / // __| '_ \  / __|/ _ \/ __/ __| |/ _ \| '_ \  | __/ _ \  | |/ _ \ / _` |/ _` |  / _` | | |
 / /_\__ \ | | | \__ \  __/\__ \__ \ | (_) | | | | | || (_) | | | (_) | (_| | (_| | | (_| | | |
/____|___/_| |_| |___/\___||___/___/_|\___/|_| |_|  \__\___/  |_|\___/ \__,_|\__,_|  \__,_|_|_|
                                                                                               
          _   _   _                       
 ___  ___| |_| |_(_)_ __   __ _ ___       
/ __|/ _ \ __| __| | '_ \ / _` / __|      
\__ \  __/ |_| |_| | | | | (_| \__ \_ _ _ 
|___/\___|\__|\__|_|_| |_|\__, |___(_|_|_)
                          |___/     
EOF

  exec zsh
}

main
