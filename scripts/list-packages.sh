#!/usr/bin/env bash

set -u

row() {
  printf '  %-38s %s\n' "$1" "$2"
}

section() {
  printf '\n%s\n' "$1"
  row "PACKAGE / COMMAND" "USE"
  row "-----------------" "---"
}

os=$(uname -s)
case "$os" in
  Darwin) platform=macOS ;;
  Linux) platform=Ubuntu/Linux ;;
  *) platform=$os ;;
esac

printf 'taj-p dotfiles toolset (%s)\n' "$platform"

section "Development tools"
row "Neovim (nvim)" "Editor; configured with AstroNvim."
row "tmux (tmux)" "Persistent terminal sessions and split panes."
row "ripgrep (rg)" "Fast recursive text and code search."
row "fd (fd)" "Fast, friendly filesystem search."
row "lazygit (lazygit, lg)" "Terminal UI for Git."
row "Tree-sitter (tree-sitter)" "Parser CLI used by Neovim syntax tooling."
row "Node.js + npm (node, npm)" "JavaScript runtime and package manager; LSP tooling."
row "Python + pip (python, python3, pip)" "Python runtime and Neovim/LSP tooling."
row "Go (go)" "Go compiler and language tooling."
row "Perl (perl)" "Runtime required by development utilities."
row "bottom (btm)" "Interactive system and process monitor."
row "go DiskUsage (gdu)" "Fast interactive disk-usage analyzer."
row "difit (difit)" "Browser-based Git diff and PR viewer."
row "zoxide (zoxide, z)" "Smarter directory jumping based on usage history."
row "lsd (lsd, ls)" "Modern directory listing with colors and icons."
row "bat (bat)" "Syntax-highlighted file viewer and cat replacement."

if [[ $os == Darwin ]]; then
  section "macOS additions"
  row "Homebrew (brew)" "Package manager used to install the toolset."
  row "JetBrainsMono Nerd Font" "Terminal font with developer icons and glyphs."
elif [[ $os == Linux ]]; then
  section "Ubuntu/Linux additions"
  row "build-essential (cc, make)" "Compiler, linker, make, and build headers."
  row "ca-certificates" "Trusted certificate authorities for HTTPS."
  row "curl (curl)" "HTTP downloads used by installers and scripts."
row "Git (git)" "Source control."
  row "unzip (unzip)" "ZIP archive extraction."
  row "xclip (xclip)" "X11 clipboard integration for Neovim."
  row "python3-venv" "Isolated Python environments."
fi

section "Optional integration"
row "gh-dash (gh dash)" "GitHub dashboard; installed when GitHub CLI is present."

section "Dotfiles commands"
row "g [git arguments]" "Short alias for git."
row "dfh [difit arguments]" "Run difit through a reusable Highway tunnel."
row "difit-highway" "Long form of dfh."
row "dotfiles-packages" "Show this package and command reminder."
row "dotfiles-sync-settings" "Update dotfiles, Neovim, and tmux together."
row "dotfiles-sync-repo" "Update and apply this dotfiles repository."
row "dotfiles-sync-nvim" "Update the Neovim configuration only."
row "dotfiles-sync-tmux" "Update the tmux configuration only."
row "dotfiles-settings-sync-loop" "Fallback updater when user systemd is unavailable."
