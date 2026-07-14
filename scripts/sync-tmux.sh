#!/usr/bin/env bash

set -Eeuo pipefail

repo=${TMUX_CONFIG_REPO:-git@github.com:taj-p/.tmux.git}
branch=${TMUX_CONFIG_BRANCH:-master}
repo_dir=${TMUX_REPO_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/tmux/oh-my-tmux}
config_dir=${TMUX_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/tmux}
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/taj-dotfiles
stamp_file="$state_dir/tmux-sync.timestamp"
interval=${TMUX_SYNC_INTERVAL_SECONDS:-600}
lock_base=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
lock_dir="$lock_base/taj-dotfiles-tmux-sync-$(id -u).lock"
changed=0

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

mkdir -p "$(dirname "$repo_dir")" "$config_dir" "$state_dir"

if [[ ! -e $repo_dir ]]; then
  printf '[tmux-sync] Cloning %s (%s)\n' "$repo" "$branch"
  git clone --branch "$branch" --single-branch "$repo" "$repo_dir"
  changed=1
elif [[ ! -d $repo_dir/.git ]]; then
  printf '[tmux-sync] Refusing to update non-Git directory: %s\n' "$repo_dir" >&2
  exit 1
else
  printf '[tmux-sync] Fetching %s\n' "$branch"
  old_head=$(git -C "$repo_dir" rev-parse HEAD)
  git -C "$repo_dir" fetch --quiet origin "$branch"
  git -C "$repo_dir" merge --ff-only --quiet "origin/$branch"
  new_head=$(git -C "$repo_dir" rev-parse HEAD)
  if [[ $old_head != "$new_head" ]]; then changed=1; fi
fi

ensure_link() {
  local target=$1 link=$2
  if [[ -L $link && $(readlink "$link") == "$target" ]]; then return 0; fi
  if [[ -e $link || -L $link ]]; then
    printf '[tmux-sync] Refusing to replace existing path: %s\n' "$link" >&2
    return 1
  fi
  ln -s "$target" "$link"
  changed=1
}

ensure_link "$repo_dir/.tmux.conf" "$config_dir/tmux.conf"
ensure_link "$repo_dir/.tmux.conf.local" "$config_dir/tmux.conf.local"

if ((changed)); then
  tmux_bin=$(command -v tmux 2>/dev/null || true)
  if [[ -z $tmux_bin && -x /opt/homebrew/bin/tmux ]]; then tmux_bin=/opt/homebrew/bin/tmux; fi
  if [[ -z $tmux_bin && -x /usr/local/bin/tmux ]]; then tmux_bin=/usr/local/bin/tmux; fi
  if [[ -n $tmux_bin ]] && "$tmux_bin" list-sessions >/dev/null 2>&1; then
    "$tmux_bin" set-environment -g TMUX_CONF "$config_dir/tmux.conf"
    "$tmux_bin" set-environment -g TMUX_CONF_LOCAL "$config_dir/tmux.conf.local"
    "$tmux_bin" source-file "$config_dir/tmux.conf" \
      || printf '[tmux-sync] Warning: active tmux server could not reload the new settings.\n' >&2
  fi
fi

date +%s >"$stamp_file"
printf '[tmux-sync] Up to date at %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
