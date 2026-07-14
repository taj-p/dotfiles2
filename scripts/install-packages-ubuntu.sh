#!/usr/bin/env bash

set -Eeuo pipefail
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib.sh
source "$ROOT_DIR/scripts/lib.sh"

if [[ $(id -u) -eq 0 ]]; then
  SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
else
  die "APT package installation needs root or sudo. Rerun with --skip-packages only if all prerequisites already exist."
fi

log "Installing Ubuntu base packages"
"${SUDO[@]}" apt-get update
DEBIAN_FRONTEND=noninteractive "${SUDO[@]}" apt-get install -y \
  build-essential ca-certificates curl fd-find git golang-go \
  perl python3 python3-pip python3-venv ripgrep tmux unzip xclip

# NodeSource's nodejs package bundles npm and declares a conflict with
# Ubuntu's separate npm package. Install them independently so this also works
# on an unmodified Ubuntu 22.04 system, where npm is a separate package.
if ! command -v node >/dev/null 2>&1; then
  log "Installing Node.js"
  DEBIAN_FRONTEND=noninteractive "${SUDO[@]}" apt-get install -y nodejs
fi
if ! command -v npm >/dev/null 2>&1; then
  node_candidate=$(apt-cache policy nodejs | awk '/Candidate:/ { print $2; exit }')
  if [[ -n $node_candidate && $node_candidate != '(none)' ]] \
    && apt-cache show "nodejs=$node_candidate" 2>/dev/null | grep -qi '^Conflicts:.*npm'; then
    die "The installed NodeSource nodejs package conflicts with Ubuntu npm but did not provide the npm command. Repair the NodeSource installation, then rerun this installer."
  fi
  log "Installing Ubuntu's separate npm package"
  DEBIAN_FRONTEND=noninteractive "${SUDO[@]}" apt-get install -y npm
fi

install -d "$HOME/.local/bin" "$HOME/.local/share"
if command -v fdfind >/dev/null 2>&1; then
  ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
fi
if command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
  ln -sfn "$(command -v python3)" "$HOME/.local/bin/python"
fi

arch=$(uname -m)
case "$arch" in
  x86_64)
    nvim_arch=x86_64
    lazygit_arch=x86_64
    bottom_arch=x86_64
    ts_arch=x64
    gdu_arch=amd64
    ;;
  aarch64 | arm64)
    nvim_arch=arm64
    lazygit_arch=arm64
    bottom_arch=aarch64
    ts_arch=arm64
    gdu_arch=arm64
    ;;
  *) die "Unsupported Ubuntu architecture: $arch" ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

log "Installing current stable Neovim under ~/.local"
curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${nvim_arch}.tar.gz" -o "$tmp/nvim.tar.gz"
tar -xzf "$tmp/nvim.tar.gz" -C "$tmp"
nvim_target="$HOME/.local/share/nvim-linux-${nvim_arch}"
rm -rf "$nvim_target"
mv "$tmp/nvim-linux-${nvim_arch}" "$nvim_target"
ln -sfn "$nvim_target/bin/nvim" "$HOME/.local/bin/nvim"

lazygit_tag=$(latest_release_tag jesseduffield/lazygit)
lazygit_version=${lazygit_tag#v}
log "Installing lazygit $lazygit_tag"
curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/${lazygit_tag}/lazygit_${lazygit_version}_linux_${lazygit_arch}.tar.gz" -o "$tmp/lazygit.tar.gz"
tar -xzf "$tmp/lazygit.tar.gz" -C "$tmp" lazygit
install -m 0755 "$tmp/lazygit" "$HOME/.local/bin/lazygit"

treesitter_tag=$(latest_release_tag tree-sitter/tree-sitter)
log "Installing Tree-sitter CLI $treesitter_tag"
curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/download/${treesitter_tag}/tree-sitter-cli-linux-${ts_arch}.zip" -o "$tmp/tree-sitter.zip"
unzip -oq "$tmp/tree-sitter.zip" -d "$tmp/tree-sitter"
install -m 0755 "$tmp/tree-sitter/tree-sitter" "$HOME/.local/bin/tree-sitter"

bottom_tag=$(latest_release_tag ClementTsang/bottom)
log "Installing bottom $bottom_tag"
curl -fsSL "https://github.com/ClementTsang/bottom/releases/download/${bottom_tag}/bottom_${bottom_arch}-unknown-linux-gnu.tar.gz" -o "$tmp/bottom.tar.gz"
tar -xzf "$tmp/bottom.tar.gz" -C "$tmp" btm
install -m 0755 "$tmp/btm" "$HOME/.local/bin/btm"

log "Installing go DiskUsage"
curl -fsSL "https://github.com/dundee/gdu/releases/latest/download/gdu_linux_${gdu_arch}.tgz" -o "$tmp/gdu.tar.gz"
tar -xzf "$tmp/gdu.tar.gz" -C "$tmp" "gdu_linux_${gdu_arch}"
install -m 0755 "$tmp/gdu_linux_${gdu_arch}" "$HOME/.local/bin/gdu"
