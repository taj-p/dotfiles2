#!/usr/bin/env bash

set -uo pipefail

difit_pid=
highway_pid=
highway_log=
publisher_pid=
printer_pid=
connection_file=

# Withdraws the dashboard link and stops the helpers that maintain it.
unpublish_link() {
  if [[ -n $publisher_pid ]] && kill -0 "$publisher_pid" >/dev/null 2>&1; then
    kill "$publisher_pid" >/dev/null 2>&1 || true
    wait "$publisher_pid" 2>/dev/null || true
  fi
  if command -v llm-watch >/dev/null 2>&1; then
    llm-watch link clear --kind difit >/dev/null 2>&1 || true
  fi
}

cleanup() {
  unpublish_link
  if [[ -n $printer_pid ]] && kill -0 "$printer_pid" >/dev/null 2>&1; then
    kill "$printer_pid" >/dev/null 2>&1 || true
    wait "$printer_pid" 2>/dev/null || true
  fi
  if [[ -n $highway_pid ]] && kill -0 "$highway_pid" >/dev/null 2>&1; then
    kill "$highway_pid" >/dev/null 2>&1 || true
    wait "$highway_pid" 2>/dev/null || true
  fi
  if [[ -n $difit_pid ]] && kill -0 "$difit_pid" >/dev/null 2>&1; then
    kill "$difit_pid" >/dev/null 2>&1 || true
    wait "$difit_pid" 2>/dev/null || true
  fi
  if [[ -n $connection_file ]]; then
    rm -f "$connection_file"
  fi
  if [[ -n $highway_log ]]; then
    rm -f "$highway_log"
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
    printf 'difit-highway: timed out waiting for difit to start\n' >&2
    exit 1
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done

cat "$connection_file"
printf 'difit-highway: starting the cached Highway tunnel for localhost:%s\n' \
  "$difit_port"

# Highway's output is captured so the tunnel URL can be published to the
# llm-watch dashboard, and replayed to the terminal so nothing is hidden.
highway_log=$(mktemp "${TMPDIR:-/tmp}/difit-highway-log.XXXXXX")
infra highway http "$difit_port" >"$highway_log" 2>&1 &
highway_pid=$!

tail -n +1 -f "$highway_log" 2>/dev/null &
printer_pid=$!

if command -v llm-watch >/dev/null 2>&1; then
  link_title=${*:-working tree}
  (
    tunnel_url=
    for _ in $(seq 1 300); do
      # Strip ANSI colour before matching so the URL is found either way.
      tunnel_url=$(sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$highway_log" |
        grep -oE 'https://[A-Za-z0-9._-]+\.highway\.[A-Za-z0-9.-]+' |
        head -n 1)
      if [[ -n $tunnel_url ]]; then
        break
      fi
      if ! kill -0 "$highway_pid" >/dev/null 2>&1; then
        exit 0
      fi
      sleep 0.2
    done
    if [[ -z $tunnel_url ]]; then
      printf 'difit-highway: could not detect the tunnel URL; dashboard link skipped\n' >&2
      exit 0
    fi
    printf 'difit-highway: dashboard link %s\n' "$tunnel_url"
    # Re-published on a heartbeat: llm-watch expires a link that stops being
    # refreshed, so a killed tunnel cannot leave a dead URL on the dashboard.
    while kill -0 "$highway_pid" >/dev/null 2>&1; do
      llm-watch link set --kind difit --url "$tunnel_url" --title "$link_title" \
        >/dev/null 2>&1 || true
      sleep 60
    done
  ) &
  publisher_pid=$!
fi

wait "$highway_pid"
highway_status=$?
highway_pid=
unpublish_link
exit "$highway_status"
