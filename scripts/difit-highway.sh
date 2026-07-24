#!/usr/bin/env bash

set -uo pipefail

route=${DIFIT_HIGHWAY_ROUTE:-taj-sense-lawn}
difit_pid=
connection_file=

cleanup() {
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
  printf 'difit-highway: difit is not on PATH\n' >&2
  exit 1
fi
if ! command -v infra >/dev/null 2>&1; then
  printf 'difit-highway: infra is not on PATH\n' >&2
  exit 1
fi
for arg in "$@"; do
  if [[ $arg == --background ]]; then
    printf 'difit-highway: --background is managed by the wrapper and cannot be passed through\n' >&2
    exit 2
  fi
done

connection_file=$(mktemp "${TMPDIR:-/tmp}/difit-highway.XXXXXX")
difit "$@" --no-open --keep-alive --host 127.0.0.1 >"$connection_file" 2>&1 &
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
    printf 'difit-highway: timed out waiting for difit to start\n' >&2
    exit 1
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done

cat "$connection_file"
printf 'difit-highway: https://%s.highway.canva-internal.dev -> localhost:%s\n' \
  "$route" "$difit_port"
infra highway run --route "$route" --port "$difit_port"
