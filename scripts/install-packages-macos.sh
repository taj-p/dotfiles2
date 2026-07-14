#!/usr/bin/env bash

set -Eeuo pipefail
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib.sh
source "$ROOT_DIR/scripts/lib.sh"

if ! xcode-select -p >/dev/null 2>&1; then
  die "Apple Command Line Tools are required. Run 'xcode-select --install', then rerun this installer."
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

log "Installing AstroNvim tools with Homebrew"
brew install neovim tmux ripgrep fd lazygit tree-sitter-cli node python go bottom gdu perl

# Homebrew avoids a coreutils name collision by installing go DiskUsage as
# gdu-go. AstroNvim calls it as gdu, so expose that name in the user bin dir.
install -d "$HOME/.local/bin"
if command -v gdu-go >/dev/null 2>&1; then
  ln -sfn "$(command -v gdu-go)" "$HOME/.local/bin/gdu"
fi
if command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
  ln -sfn "$(command -v python3)" "$HOME/.local/bin/python"
fi

if ! brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
  log "Installing JetBrainsMono Nerd Font"
  brew install --cask font-jetbrains-mono-nerd-font || warn "Nerd Font installation failed; it can be installed later with Homebrew."
fi
