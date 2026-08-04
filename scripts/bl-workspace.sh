#!/usr/bin/env sh

set -eu

session=bl
project_dir="$HOME/bl"
bl_binary="$HOME/repos/bl/target/release/bl"

find_command() {
  command -v "$1" 2>/dev/null && return 0
  for candidate in "/opt/homebrew/bin/$1" "/usr/local/bin/$1"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

tmux_bin=$(find_command tmux) || {
  printf 'bl-workspace: tmux is not installed or is not on PATH\n' >&2
  exit 1
}

if ! "$tmux_bin" has-session -t "$session" 2>/dev/null; then
  nvim_bin=$(find_command nvim) || {
    printf 'bl-workspace: nvim is not installed or is not on PATH\n' >&2
    exit 1
  }

  if [ ! -d "$project_dir" ]; then
    printf 'bl-workspace: project directory does not exist: %s\n' "$project_dir" >&2
    exit 1
  fi

  if [ ! -x "$bl_binary" ]; then
    printf 'bl-workspace: executable does not exist: %s\n' "$bl_binary" >&2
    exit 1
  fi

  "$tmux_bin" new-session \
    -d \
    -s "$session" \
    -n tasks \
    -c "$project_dir" \
    "$nvim_bin tasks.md"

  "$tmux_bin" new-window \
    -d \
    -t "$session:" \
    -n server \
    -c "$project_dir" \
    "$bl_binary start"

  "$tmux_bin" select-window -t "$session:tasks"
fi

exec "$tmux_bin" attach-session -t "$session"
