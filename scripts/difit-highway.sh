#!/usr/bin/env bash

set -uo pipefail

prog=difit-highway
difit_pid=
connection_file=

lib="$HOME/.local/libexec/taj-dotfiles/highway-tunnel.sh"
if [[ ! -r $lib ]]; then
  printf '%s: tunnel helper is missing: %s\n' "$prog" "$lib" >&2
  exit 1
fi
# shellcheck source=highway-tunnel.sh
source "$lib"

cleanup() {
  highway_tunnel_cleanup
  if [[ -n $difit_pid ]] && kill -0 "$difit_pid" >/dev/null 2>&1; then
    kill "$difit_pid" >/dev/null 2>&1 || true
    wait "$difit_pid" 2>/dev/null || true
  fi
  if [[ -n $connection_file ]]; then
    rm -f "$connection_file"
  fi
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

if ! command -v difit >/dev/null 2>&1; then
  printf '%s: difit is not on PATH\n' "$prog" >&2
  exit 1
fi
if ! command -v infra >/dev/null 2>&1; then
  printf '%s: infra is not on PATH\n' "$prog" >&2
  exit 1
fi
for arg in "$@"; do
  if [[ $arg == --background ]]; then
    printf '%s: --background is managed by the wrapper and cannot be passed through\n' \
      "$prog" >&2
    exit 2
  fi
done

difit_args=("$@")
if [[ ${1:-} =~ ^https://github\.com/[^/]+/[^/]+/pull/[0-9]+(/changes)?/?$ ]]; then
  pr_url=${1%/}
  pr_url=${pr_url%/changes}
  difit_args=(--pr "$pr_url" "${@:2}")
fi

connection_file=$(mktemp "${TMPDIR:-/tmp}/difit-highway.XXXXXX")
difit "${difit_args[@]}" --no-open --keep-alive --host 127.0.0.1 >"$connection_file" 2>&1 &
difit_pid=$!

attempt=0
difit_port=
while [[ -z $difit_port ]]; do
  difit_port=$(sed -n \
    's/.*server started on http:\/\/[^:]*:\([0-9][0-9]*\).*/\1/p' \
    "$connection_file")
  if ! kill -0 "$difit_pid" >/dev/null 2>&1; then
    cat "$connection_file"
    wait "$difit_pid"
    exit $?
  fi
  if ((attempt >= 100)); then
    cat "$connection_file" >&2
    printf '%s: timed out waiting for difit to start\n' "$prog" >&2
    exit 1
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done

cat "$connection_file"
highway_tunnel_start "$difit_port" "${*:-working tree}"

highway_tunnel_wait
exit $?
