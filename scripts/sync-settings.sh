#!/usr/bin/env bash

set -u

status=0
"$HOME/.local/bin/dotfiles-sync-nvim" "$@" || status=1
"$HOME/.local/bin/dotfiles-sync-tmux" "$@" || status=1
exit "$status"

