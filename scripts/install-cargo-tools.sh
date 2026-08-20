#!/usr/bin/env bash

set -Eeuo pipefail
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib.sh
source "$ROOT_DIR/scripts/lib.sh"

find_cargo() {
  local candidate
  candidate=$(command -v cargo 2>/dev/null || true)
  if [[ -n $candidate ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  for candidate in \
    "$HOME/.cargo/bin/cargo" \
    /opt/homebrew/bin/cargo \
    /usr/local/bin/cargo; do
    if [[ -x $candidate ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

rustup_installer=
cleanup() {
  if [[ -n $rustup_installer ]]; then rm -f "$rustup_installer"; fi
}
trap cleanup EXIT

cargo_bin=$(find_cargo || true)
if [[ -z $cargo_bin ]]; then
  log "Installing the minimal Rust toolchain with rustup"
  rustup_installer=$(mktemp "${TMPDIR:-/tmp}/dotfiles-rustup.XXXXXX")
  curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs -o "$rustup_installer"
  sh "$rustup_installer" -y --profile minimal --no-modify-path
  rm -f "$rustup_installer"
  rustup_installer=
  cargo_bin="$HOME/.cargo/bin/cargo"
fi

[[ -x $cargo_bin ]] || die "Cargo is required to install the managed Cargo tools."
log "Installing cargo-watch with Cargo"
"$cargo_bin" install --locked cargo-watch
log "Installing wasm-bindgen-cli 0.2.123 with Cargo"
"$cargo_bin" install wasm-bindgen-cli@0.2.123
