#!/usr/bin/env bash

log() { printf '[dotfiles] %s\n' "$*"; }
warn() { printf '[dotfiles] warning: %s\n' "$*" >&2; }
die() { printf '[dotfiles] error: %s\n' "$*" >&2; exit 1; }

ensure_line() {
  local file=$1 line=$2
  touch "$file"
  grep -Fqx "$line" "$file" 2>/dev/null || printf '\n%s\n' "$line" >>"$file"
}

latest_release_tag() {
  local repo=$1 url
  url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")
  printf '%s\n' "${url##*/}"
}

backup_path() {
  local path=$1 stamp backup counter
  [[ -e $path || -L $path ]] || return 0
  stamp=$(date '+%Y%m%d-%H%M%S')
  backup="${path}.backup-${stamp}"
  counter=0
  while [[ -e $backup || -L $backup ]]; do
    counter=$((counter + 1))
    backup="${path}.backup-${stamp}-${counter}"
  done
  log "Moving existing path to $backup"
  mv "$path" "$backup"
}

prepare_nvim_config_dir() {
  local config_dir expected_remote actual_remote backup stamp counter
  config_dir=${NVIM_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/nvim}
  expected_remote=${NVIM_CONFIG_REPO:-https://github.com/taj-p/nvim_config.git}

  [[ -e $config_dir ]] || return 0
  if [[ -d $config_dir/.git ]]; then
    actual_remote=$(git -C "$config_dir" remote get-url origin 2>/dev/null || true)
    if [[ ${actual_remote%.git} == "${expected_remote%.git}" ]]; then
      return 0
    fi
  fi

  stamp=$(date '+%Y%m%d-%H%M%S')
  backup="${config_dir}.backup-${stamp}"
  counter=0
  while [[ -e $backup ]]; do
    counter=$((counter + 1))
    backup="${config_dir}.backup-${stamp}-${counter}"
  done
  log "Moving existing Neovim config to $backup"
  mv "$config_dir" "$backup"
}

prepare_tmux_config() {
  local repo_dir config_dir expected_remote actual_remote target link legacy
  repo_dir=${TMUX_REPO_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/tmux/oh-my-tmux}
  config_dir=${TMUX_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/tmux}
  expected_remote=${TMUX_CONFIG_REPO:-git@github.com:taj-p/.tmux.git}

  if [[ -e $repo_dir ]]; then
    actual_remote=
    if [[ -d $repo_dir/.git ]]; then
      actual_remote=$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)
    fi
    if [[ ${actual_remote%.git} != "${expected_remote%.git}" ]]; then
      backup_path "$repo_dir"
    fi
  fi

  for legacy in "$HOME/.tmux.conf" "$HOME/.tmux.conf.local"; do
    if [[ -e $legacy || -L $legacy ]]; then backup_path "$legacy"; fi
  done

  for link in "$config_dir/tmux.conf" "$config_dir/tmux.conf.local"; do
    if [[ $link == *.local ]]; then
      target="$repo_dir/.tmux.conf.local"
    else
      target="$repo_dir/.tmux.conf"
    fi
    if [[ -L $link && $(readlink "$link") == "$target" ]]; then continue; fi
    if [[ -e $link || -L $link ]]; then backup_path "$link"; fi
  done
}

install_macos_scheduler() {
  local src dest domain
  src="$ROOT_DIR/scheduler/macos/com.tajp.dotfiles-settings-sync.plist"
  dest="$HOME/Library/LaunchAgents/com.tajp.dotfiles-settings-sync.plist"
  domain="gui/$(id -u)"
  install -d "$HOME/Library/LaunchAgents" "$HOME/.local/state/taj-dotfiles"
  sed "s|__HOME__|$HOME|g" "$src" >"$dest"
  launchctl bootout "$domain/com.tajp.nvim-config-sync" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/LaunchAgents/com.tajp.nvim-config-sync.plist"
  launchctl bootout "$domain/com.tajp.dotfiles-settings-sync" >/dev/null 2>&1 || true
  if ! launchctl bootstrap "$domain" "$dest"; then
    warn "Modern launchctl bootstrap failed; trying the compatibility loader."
    launchctl load -w "$dest"
  fi
  launchctl kickstart -k "$domain/com.tajp.dotfiles-settings-sync" >/dev/null 2>&1 || true
  log "Installed macOS 10-minute settings LaunchAgent"
}

install_linux_scheduler() {
  local unit_dir
  unit_dir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
  install -d "$unit_dir"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now nvim-config-sync.timer >/dev/null 2>&1 || true
  fi
  rm -f "$unit_dir/nvim-config-sync.service" "$unit_dir/nvim-config-sync.timer"
  install -m 0644 "$ROOT_DIR/scheduler/linux/dotfiles-settings-sync.service" "$unit_dir/dotfiles-settings-sync.service"
  install -m 0644 "$ROOT_DIR/scheduler/linux/dotfiles-settings-sync.timer" "$unit_dir/dotfiles-settings-sync.timer"

  if command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload >/dev/null 2>&1; then
    systemctl --user enable --now dotfiles-settings-sync.timer
    log "Installed user systemd 10-minute settings timer"
  else
    warn "No user systemd session detected; starting the Coder/container fallback loop."
    nohup "$HOME/.local/bin/dotfiles-settings-sync-loop" \
      >>"$HOME/.local/state/taj-dotfiles/settings-sync-loop.log" 2>&1 &
  fi
}
