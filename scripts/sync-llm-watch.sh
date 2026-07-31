#!/usr/bin/env bash

set -Eeuo pipefail

repo=${LLM_WATCH_REPO:-git@github.com:taj-p/llm-watch.git}
branch=${LLM_WATCH_BRANCH:-main}
repo_dir=${LLM_WATCH_REPO_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/llm-watch}
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/taj-dotfiles
stamp_file="$state_dir/llm-watch-sync.timestamp"
interval=${LLM_WATCH_SYNC_INTERVAL_SECONDS:-600}
lock_base=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
lock_dir="$lock_base/taj-dotfiles-llm-watch-sync-$(id -u).lock"

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

mkdir -p "$(dirname "$repo_dir")" "$HOME/.local/bin" "$state_dir"

if [[ ! -e $repo_dir ]]; then
  printf '[llm-watch-sync] Cloning %s (%s)\n' "$repo" "$branch"
  git clone --branch "$branch" --single-branch "$repo" "$repo_dir"
elif [[ ! -d $repo_dir/.git ]]; then
  printf '[llm-watch-sync] Refusing to update non-Git directory: %s\n' "$repo_dir" >&2
  exit 1
else
  printf '[llm-watch-sync] Fetching %s\n' "$branch"
  git -C "$repo_dir" fetch --quiet origin "$branch"
  git -C "$repo_dir" merge --ff-only --quiet "origin/$branch"
fi

target="$repo_dir/bin/llm-watch"
link="$HOME/.local/bin/llm-watch"
if [[ ! -x $target ]]; then
  printf '[llm-watch-sync] Expected executable is missing: %s\n' "$target" >&2
  exit 1
fi
if [[ -L $link ]]; then
  if [[ $(readlink "$link") != "$target" ]]; then
    ln -sfn "$target" "$link"
  fi
elif [[ -e $link ]]; then
  printf '[llm-watch-sync] Refusing to replace existing path: %s\n' "$link" >&2
  exit 1
else
  ln -s "$target" "$link"
fi

configurer="$HOME/.local/libexec/taj-dotfiles/configure-llm-watch.py"
if [[ ! -x $configurer ]]; then
  printf '[llm-watch-sync] Hook configurer is missing: %s\n' "$configurer" >&2
  exit 1
fi
python3 "$configurer"

date +%s >"$stamp_file"
printf '[llm-watch-sync] Up to date at %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
