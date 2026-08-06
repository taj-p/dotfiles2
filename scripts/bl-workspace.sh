#!/usr/bin/env sh

set -eu

project_dir="$HOME/bl"
bl_binary="$HOME/repos/backlog/target/release/bl"

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

session=bl
if ! "$tmux_bin" has-session -t "$session" 2>/dev/null; then
  existing_session=$(
    "$tmux_bin" list-panes -a \
      -F '#{session_name}|#{pane_current_path}|#{pane_current_command}' 2>/dev/null |
      awk -F '|' -v project_dir="$project_dir" \
        '$2 == project_dir && $3 == "nvim" { print $1; exit }'
  )
  if [ -n "$existing_session" ]; then
    session=$existing_session
  fi
fi

if ! "$tmux_bin" has-session -t "$session" 2>/dev/null; then
  nvim_bin=$(find_command nvim) || {
    printf 'bl-workspace: nvim is not installed or is not on PATH\n' >&2
    exit 1
  }

  if [ ! -d "$project_dir" ]; then
    printf 'bl-workspace: project directory does not exist: %s\n' "$project_dir" >&2
    exit 1
  fi

  "$tmux_bin" new-session \
    -d \
    -s "$session" \
    -n tasks \
    -c "$project_dir" \
    "$nvim_bin tasks.md"

  if [ -x "$bl_binary" ]; then
    "$tmux_bin" new-window \
      -d \
      -t "$session:" \
      -n server \
      -c "$project_dir" \
      "$bl_binary start"
  else
    printf 'bl-workspace: skipping server window; executable does not exist: %s\n' \
      "$bl_binary" >&2
  fi

  "$tmux_bin" select-window -t "$session:tasks"
fi

task_target=$(
  "$tmux_bin" list-panes -a \
    -F '#{session_name}|#{window_index}|#{pane_index}|#{pane_current_path}|#{pane_current_command}' 2>/dev/null |
    awk -F '|' -v session="$session" -v project_dir="$project_dir" \
      '$1 == session && $4 == project_dir && $5 == "nvim" { print $1 ":" $2 "." $3; exit }'
)
if [ -n "$task_target" ]; then
  "$tmux_bin" select-window -t "${task_target%.*}"
  "$tmux_bin" select-pane -t "$task_target"
fi

exec "$tmux_bin" attach-session -t "$session"
