#!/usr/bin/env bash

set -u

status=0
if [[ ${DOTFILES_SELF_UPDATE:-0} != 1 ]]; then
  "$HOME/.local/bin/dotfiles-sync-repo" "$@" || status=1
fi
"$HOME/.local/bin/dotfiles-sync-nvim" "$@" || status=1
"$HOME/.local/bin/dotfiles-sync-tmux" "$@" || status=1
exit "$status"
