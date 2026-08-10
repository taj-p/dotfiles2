#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib.sh
source "$ROOT_DIR/scripts/lib.sh"

while (($#)); do
  case "$1" in
    --skip-packages) DOTFILES_SKIP_PACKAGES=1 ;;
    --skip-nvim-init) DOTFILES_SKIP_NVIM_INIT=1 ;;
    --no-scheduler) DOTFILES_NO_SCHEDULER=1 ;;
    -h | --help)
      cat <<'EOF'
Usage: ./install.sh [options]

  --skip-packages   Do not install or upgrade command-line tools
  --skip-nvim-init  Do not initialize AstroNvim plugins headlessly
  --no-scheduler    Do not install the 10-minute config update service
  -h, --help        Show this help
EOF
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

OS=${DOTFILES_OS:-$(uname -s)}
case "$OS" in
  Darwin | macos) OS=macos ;;
  Linux | linux)
    OS=linux
    if [[ -r /etc/os-release ]]; then
      # shellcheck disable=SC1091
      source /etc/os-release
      [[ ${ID:-} == ubuntu ]] || warn "Linux distribution '${ID:-unknown}' is not tested; continuing with the Ubuntu installer."
    fi
    ;;
  *) die "Unsupported operating system: $OS" ;;
esac

log "Installing taj-p dotfiles for $OS"

if [[ ${DOTFILES_SKIP_PACKAGES:-0} != 1 ]]; then
  if [[ $OS == macos ]]; then
    "$ROOT_DIR/scripts/install-packages-macos.sh"
  else
    "$ROOT_DIR/scripts/install-packages-ubuntu.sh"
  fi
else
  log "Skipping package installation"
fi

install_difit=0
if [[ ${DOTFILES_SKIP_PACKAGES:-0} != 1 ]]; then
  install_difit=1
elif [[ ${DOTFILES_SELF_UPDATE:-0} == 1 && ! -x "$HOME/.local/bin/difit" ]]; then
  log "difit is missing; installing it during the dotfiles update"
  install_difit=1
fi
if [[ $install_difit == 1 ]]; then
  if ! command -v npm >/dev/null 2>&1; then
    die "npm is required to install difit."
  fi
  log "Installing difit with npm"
  npm install --global --prefix "$HOME/.local" difit
fi

has_shell_tool() {
  command -v "$1" >/dev/null 2>&1 \
    || [[ -x "$HOME/.local/bin/$1" ]] \
    || [[ -x "/opt/homebrew/bin/$1" ]] \
    || [[ -x "/usr/local/bin/$1" ]]
}

install_shell_tools=0
if [[ ${DOTFILES_SKIP_PACKAGES:-0} != 1 ]]; then
  install_shell_tools=1
elif [[ ${DOTFILES_SELF_UPDATE:-0} == 1 ]] \
  && { ! has_shell_tool zoxide \
    || ! has_shell_tool lsd \
    || ! has_shell_tool bat; }; then
  log "Modern shell tools are missing; installing them during the dotfiles update"
  install_shell_tools=1
fi
if [[ $install_shell_tools == 1 ]]; then
  "$ROOT_DIR/scripts/install-shell-tools.sh"
fi

install -d \
  "$HOME/.local/bin" \
  "$HOME/.local/libexec/taj-dotfiles" \
  "$HOME/.local/state/taj-dotfiles" \
  "$HOME/.config/taj-dotfiles"
"$ROOT_DIR/scripts/install-agent-skills.sh"
install_lazygit_config
install_choochoo_config
install -m 0755 "$ROOT_DIR/scripts/sync-dotfiles.sh" "$HOME/.local/bin/dotfiles-sync-repo"
install -m 0755 "$ROOT_DIR/scripts/sync-nvim.sh" "$HOME/.local/bin/dotfiles-sync-nvim"
install -m 0755 "$ROOT_DIR/scripts/sync-tmux.sh" "$HOME/.local/bin/dotfiles-sync-tmux"
install -m 0755 "$ROOT_DIR/scripts/sync-llm-watch.sh" "$HOME/.local/bin/dotfiles-sync-llm-watch"
install -m 0755 "$ROOT_DIR/scripts/sync-choochoo.sh" "$HOME/.local/bin/dotfiles-sync-choochoo"
install -m 0755 "$ROOT_DIR/scripts/sync-settings.sh" "$HOME/.local/bin/dotfiles-sync-settings"
install -m 0755 "$ROOT_DIR/scripts/sync-settings-loop.sh" "$HOME/.local/bin/dotfiles-settings-sync-loop"
install -m 0755 "$ROOT_DIR/scripts/difit-highway.sh" "$HOME/.local/bin/difit-highway"
install -m 0755 "$ROOT_DIR/scripts/difit-highway.sh" "$HOME/.local/bin/dfh"
install -m 0755 "$ROOT_DIR/scripts/list-packages.sh" "$HOME/.local/bin/dotfiles-packages"
install -m 0755 "$ROOT_DIR/scripts/quick-checkout.sh" "$HOME/.local/bin/qco"
install -m 0755 "$ROOT_DIR/scripts/codex-review-head.sh" "$HOME/.local/bin/codex-review-head"
install -m 0755 "$ROOT_DIR/scripts/codex-review-head.sh" "$HOME/.local/bin/crh"
install -m 0755 "$ROOT_DIR/scripts/devbox-pr-review.py" "$HOME/.local/bin/devbox-pr-review"
install -m 0755 "$ROOT_DIR/scripts/devbox-pr-review.py" "$HOME/.local/bin/dpr"
install -m 0755 "$ROOT_DIR/scripts/llm-watch-codex-stop-hook.sh" "$HOME/.local/bin/llm-watch-codex-stop-hook"
if [[ $OS == macos ]]; then
  install -m 0755 "$ROOT_DIR/scripts/bl-workspace.sh" "$HOME/.local/bin/bl-workspace"
  install_wezterm_config
fi
install -m 0755 \
  "$ROOT_DIR/scripts/configure-llm-watch.py" \
  "$HOME/.local/libexec/taj-dotfiles/configure-llm-watch.py"
install -m 0644 "$ROOT_DIR/shell/profile.sh" "$HOME/.config/taj-dotfiles/profile.sh"
printf '%s\n' "$ROOT_DIR" >"$HOME/.config/taj-dotfiles/repo-dir"

if [[ ${DOTFILES_SKIP_PACKAGES:-0} != 1 ]]; then
  install_gh_dash
fi

source_line='[ -r "$HOME/.config/taj-dotfiles/profile.sh" ] && . "$HOME/.config/taj-dotfiles/profile.sh"'
ensure_line "$HOME/.bashrc" "$source_line"
ensure_line "$HOME/.zshrc" "$source_line"

if [[ $OS == macos ]]; then
  export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"
else
  export PATH="$HOME/.local/bin:$PATH"
fi
if [[ ${DOTFILES_SELF_UPDATE:-0} != 1 ]]; then
  prepare_nvim_config_dir
  prepare_tmux_config
  NVIM_CONFIG_REPO="${NVIM_CONFIG_REPO:-https://github.com/taj-p/nvim_config.git}" \
    NVIM_CONFIG_BRANCH="${NVIM_CONFIG_BRANCH:-main}" \
    NVIM_CONFIG_DIR="${NVIM_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/nvim}" \
    TMUX_CONFIG_REPO="${TMUX_CONFIG_REPO:-git@github.com:taj-p/.tmux.git}" \
    TMUX_CONFIG_BRANCH="${TMUX_CONFIG_BRANCH:-master}" \
    TMUX_REPO_DIR="${TMUX_REPO_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/tmux/oh-my-tmux}" \
    TMUX_CONFIG_DIR="${TMUX_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/tmux}" \
    LLM_WATCH_REPO="${LLM_WATCH_REPO:-https://github.com/taj-p/llm-watch.git}" \
    LLM_WATCH_BRANCH="${LLM_WATCH_BRANCH:-main}" \
    LLM_WATCH_REPO_DIR="${LLM_WATCH_REPO_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/llm-watch}" \
    CHOOCHOO_REPO="${CHOOCHOO_REPO:-https://github.com/taj-p/choochoo.git}" \
    CHOOCHOO_BRANCH="${CHOOCHOO_BRANCH:-main}" \
    CHOOCHOO_REPO_DIR="${CHOOCHOO_REPO_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/choochoo}" \
    "$HOME/.local/bin/dotfiles-sync-settings"
else
  "$HOME/.local/bin/dotfiles-sync-llm-watch"
  "$HOME/.local/bin/dotfiles-sync-choochoo"
fi

if [[ ${DOTFILES_NO_SCHEDULER:-0} != 1 ]]; then
  if [[ $OS == macos ]]; then
    install_macos_scheduler
  else
    install_linux_scheduler
  fi
else
  log "Skipping config update scheduler"
fi

if [[ ${DOTFILES_SKIP_NVIM_INIT:-0} != 1 ]]; then
  if command -v nvim >/dev/null 2>&1; then
    log "Initializing AstroNvim (the first run can take a few minutes)"
    nvim --headless "+qa" || warn "Neovim initialization reported an error; run 'nvim' to finish setup interactively."
  else
    warn "nvim is not on PATH, so AstroNvim initialization was skipped."
  fi
fi

if git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ROOT_DIR" rev-parse HEAD >"$HOME/.local/state/taj-dotfiles/repo-applied-revision"
fi

log "Done. Open a new shell, then run 'nvim' or 'tmux'."
