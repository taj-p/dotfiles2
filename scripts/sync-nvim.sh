#!/usr/bin/env bash

set -Eeuo pipefail

repo=${NVIM_CONFIG_REPO:-https://github.com/taj-p/nvim_config.git}
branch=${NVIM_CONFIG_BRANCH:-main}
config_dir=${NVIM_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/nvim}
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/taj-dotfiles
stamp_file="$state_dir/nvim-sync.timestamp"
interval=${NVIM_SYNC_INTERVAL_SECONDS:-600}
lock_base=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
lock_dir="$lock_base/taj-dotfiles-nvim-sync-$(id -u).lock"

if [[ ${1:-} == --if-due && -r $stamp_file ]]; then
  now=$(date +%s)
  read -r last <"$stamp_file" || last=0
  if ((now - last < interval)); then exit 0; fi
fi

if ! mkdir "$lock_dir" 2>/dev/null; then
  if [[ -r $lock_dir/pid ]]; then
    read -r lock_pid <"$lock_dir/pid" || lock_pid=0
    if [[ $lock_pid =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null; then exit 0; fi
  fi
  rm -f "$lock_dir/pid"
  rmdir "$lock_dir" 2>/dev/null || exit 0
  mkdir "$lock_dir" 2>/dev/null || exit 0
fi
printf '%s\n' "$$" >"$lock_dir/pid"
cleanup() { rm -f "$lock_dir/pid"; rmdir "$lock_dir" 2>/dev/null || true; }
trap cleanup EXIT

mkdir -p "$(dirname "$config_dir")" "$state_dir"

if [[ ! -e $config_dir ]]; then
  printf '[nvim-sync] Cloning %s (%s)\n' "$repo" "$branch"
  git clone --branch "$branch" --single-branch "$repo" "$config_dir"
elif [[ ! -d $config_dir/.git ]]; then
  printf '[nvim-sync] Refusing to update non-Git directory: %s\n' "$config_dir" >&2
  exit 1
else
  printf '[nvim-sync] Fetching %s\n' "$branch"
  git -C "$config_dir" fetch --quiet origin "$branch"
  git -C "$config_dir" merge --ff-only --quiet "origin/$branch"
fi

date +%s >"$stamp_file"
printf '[nvim-sync] Up to date at %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
