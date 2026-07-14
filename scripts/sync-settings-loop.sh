#!/usr/bin/env bash

set -u

state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/taj-dotfiles
lock_dir="$state_dir/settings-sync-loop.lock"
mkdir -p "$state_dir"
if ! mkdir "$lock_dir" 2>/dev/null; then
  if [ -r "$lock_dir/pid" ]; then
    read -r lock_pid <"$lock_dir/pid" || lock_pid=0
    if [ "$lock_pid" -gt 0 ] 2>/dev/null && kill -0 "$lock_pid" 2>/dev/null; then exit 0; fi
  fi
  rm -f "$lock_dir/pid"
  rmdir "$lock_dir" 2>/dev/null || exit 0
  mkdir "$lock_dir" 2>/dev/null || exit 0
fi
printf '%s\n' "$$" >"$lock_dir/pid"
cleanup() { rm -f "$lock_dir/pid"; rmdir "$lock_dir" 2>/dev/null || true; }
stop() {
  if [ -n "${sleep_pid:-}" ]; then kill "$sleep_pid" 2>/dev/null || true; fi
  exit 0
}
trap cleanup EXIT
trap stop INT TERM

while :; do
  "$HOME/.local/bin/dotfiles-sync-settings" || true
  sleep "${DOTFILES_SYNC_INTERVAL_SECONDS:-600}" &
  sleep_pid=$!
  wait "$sleep_pid" || true
  sleep_pid=
done

