#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib.sh
source "$ROOT_DIR/scripts/lib.sh"

source_dir="$ROOT_DIR/agent-skills"
destinations=(
  "$HOME/.agents/skills"
  "$HOME/.claude/skills"
)

install -d "${destinations[@]}"

for source in "$source_dir"/*; do
  [[ -d $source ]] || continue
  if [[ ! -r $source/SKILL.md ]]; then
    warn "Skipping agent skill without a readable SKILL.md: $source"
    continue
  fi

  name=${source##*/}
  for destination in "${destinations[@]}"; do
    target="$destination/$name"
    if [[ -L $target && $(readlink "$target") == "$source" ]]; then
      continue
    fi
    if [[ -e $target || -L $target ]]; then
      backup_path "$target"
    fi
    ln -s "$source" "$target"
    log "Installed shared agent skill $name at $target"
  done
done
