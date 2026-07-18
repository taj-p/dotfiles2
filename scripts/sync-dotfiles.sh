#!/usr/bin/env bash

set -Eeuo pipefail

config_dir=$HOME/.config/taj-dotfiles
repo_file="$config_dir/repo-dir"
repo_dir=${DOTFILES_REPO_DIR:-}
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/taj-dotfiles
stamp_file="$state_dir/repo-sync.timestamp"
applied_file="$state_dir/repo-applied-revision"
interval=${DOTFILES_REPO_SYNC_INTERVAL_SECONDS:-600}
lock_base=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
lock_dir="$lock_base/taj-dotfiles-repo-sync-$(id -u).lock"

if [[ -z $repo_dir ]]; then
  if [[ ! -r $repo_file ]]; then
    printf '[dotfiles-sync] Repository path is not configured; rerun install.sh.\n' >&2
    exit 1
  fi
  IFS= read -r repo_dir <"$repo_file"
fi

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

mkdir -p "$state_dir"

if ! git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
  printf '[dotfiles-sync] Refusing to update non-Git directory: %s\n' "$repo_dir" >&2
  exit 1
fi

branch=$(git -C "$repo_dir" symbolic-ref --quiet --short HEAD) || {
  printf '[dotfiles-sync] Refusing to update a detached checkout: %s\n' "$repo_dir" >&2
  exit 1
}

printf '[dotfiles-sync] Fetching %s\n' "$branch"
git -C "$repo_dir" fetch --quiet origin "$branch"
git -C "$repo_dir" merge --ff-only --quiet FETCH_HEAD
new_head=$(git -C "$repo_dir" rev-parse HEAD)
applied_head=
if [[ -r $applied_file ]]; then
  read -r applied_head <"$applied_file" || applied_head=
fi

if [[ $applied_head != "$new_head" ]]; then
  printf '[dotfiles-sync] Applying dotfiles revision %s\n' "${new_head:0:12}"
  DOTFILES_SELF_UPDATE=1 "$repo_dir/install.sh" \
    --skip-packages --skip-nvim-init --no-scheduler
fi

date +%s >"$stamp_file"
printf '[dotfiles-sync] Up to date at %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
