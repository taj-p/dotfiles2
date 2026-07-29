#!/usr/bin/env bash

set -Eeuo pipefail

arg=${1:-}
if [[ $# -ne 1 || $arg == -h || $arg == --help ]]; then
  printf 'Usage: qco <remote-ref>\n'
  printf 'Fetch a ref from origin and check out the resulting FETCH_HEAD.\n'
  if [[ $# -eq 1 && ($arg == -h || $arg == --help) ]]; then
    exit 0
  fi
  exit 2
fi

git fetch origin "$arg"
git checkout FETCH_HEAD
