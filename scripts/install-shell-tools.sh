#!/usr/bin/env bash

set -Eeuo pipefail
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib.sh
source "$ROOT_DIR/scripts/lib.sh"

os=${DOTFILES_OS:-$(uname -s)}
case "$os" in
  Darwin | macos)
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
    command -v brew >/dev/null 2>&1 || die "Homebrew is required to install zoxide, lsd, bat, and Mergiraf on macOS."
    log "Installing modern shell tools with Homebrew"
    brew install zoxide lsd bat mergiraf
    ;;
  Linux | linux)
    arch=$(uname -m)
    case "$arch" in
      x86_64) release_arch=x86_64 ;;
      aarch64 | arm64) release_arch=aarch64 ;;
      *) die "Unsupported Linux architecture for shell tools: $arch" ;;
    esac
    release_target="${release_arch}-unknown-linux-musl"

    install -d "$HOME/.local/bin"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    zoxide_tag=$(latest_release_tag ajeetdsouza/zoxide)
    zoxide_version=${zoxide_tag#v}
    log "Installing zoxide $zoxide_tag"
    curl -fsSL \
      "https://github.com/ajeetdsouza/zoxide/releases/download/${zoxide_tag}/zoxide-${zoxide_version}-${release_target}.tar.gz" \
      -o "$tmp/zoxide.tar.gz"
    mkdir "$tmp/zoxide"
    tar -xzf "$tmp/zoxide.tar.gz" -C "$tmp/zoxide"
    install -m 0755 "$tmp/zoxide/zoxide" "$HOME/.local/bin/zoxide"

    lsd_tag=$(latest_release_tag lsd-rs/lsd)
    lsd_version=${lsd_tag#v}
    lsd_dir="lsd-v${lsd_version}-${release_target}"
    log "Installing lsd $lsd_tag"
    curl -fsSL \
      "https://github.com/lsd-rs/lsd/releases/download/${lsd_tag}/${lsd_dir}.tar.gz" \
      -o "$tmp/lsd.tar.gz"
    tar -xzf "$tmp/lsd.tar.gz" -C "$tmp"
    install -m 0755 "$tmp/$lsd_dir/lsd" "$HOME/.local/bin/lsd"

    bat_tag=$(latest_release_tag sharkdp/bat)
    bat_version=${bat_tag#v}
    bat_dir="bat-v${bat_version}-${release_target}"
    log "Installing bat $bat_tag"
    curl -fsSL \
      "https://github.com/sharkdp/bat/releases/download/${bat_tag}/${bat_dir}.tar.gz" \
      -o "$tmp/bat.tar.gz"
    tar -xzf "$tmp/bat.tar.gz" -C "$tmp"
    install -m 0755 "$tmp/$bat_dir/bat" "$HOME/.local/bin/bat"

    "$HOME/.local/bin/zoxide" --version
    "$HOME/.local/bin/lsd" --version
    "$HOME/.local/bin/bat" --version

    mergiraf_target="${release_arch}-unknown-linux-gnu"
    log "Installing the latest Mergiraf release"
    curl -fsSL \
      "https://codeberg.org/mergiraf/mergiraf/releases/download/latest/mergiraf_${mergiraf_target}.tar.gz" \
      -o "$tmp/mergiraf.tar.gz"
    tar -xzf "$tmp/mergiraf.tar.gz" -C "$tmp" mergiraf
    install -m 0755 "$tmp/mergiraf" "$HOME/.local/bin/mergiraf"
    "$HOME/.local/bin/mergiraf" --version
    ;;
  *) die "Unsupported operating system for shell tools: $os" ;;
esac
