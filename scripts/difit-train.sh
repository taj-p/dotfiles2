#!/usr/bin/env bash

# Reviews a whole choochoo train through one Highway tunnel: one difit per
# branch, each against its parent, behind a router that picks the right one
# from a cookie. See scripts/difit-train-router.mjs for why it is a cookie.

set -uo pipefail

prog=difit-train
router_pid=
connection_file=
# The router's index is the entry point, not difit's root, so that is what the
# dashboard link should point at.
highway_link_path=/_train

lib="$HOME/.local/libexec/taj-dotfiles/highway-tunnel.sh"
router="$HOME/.local/libexec/taj-dotfiles/difit-train-router.mjs"
if [[ ! -r $lib ]]; then
  printf '%s: tunnel helper is missing: %s\n' "$prog" "$lib" >&2
  exit 1
fi
if [[ ! -r $router ]]; then
  printf '%s: router is missing: %s\n' "$prog" "$router" >&2
  exit 1
fi
# shellcheck source=highway-tunnel.sh
source "$lib"

cleanup() {
  highway_tunnel_cleanup
  if [[ -n $router_pid ]] && kill -0 "$router_pid" >/dev/null 2>&1; then
    # The router reaps its own difit children on SIGTERM.
    kill "$router_pid" >/dev/null 2>&1 || true
    wait "$router_pid" 2>/dev/null || true
  fi
  if [[ -n $connection_file ]]; then
    rm -f "$connection_file"
  fi
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

for tool in choo difit infra node; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf '%s: %s is not on PATH\n' "$prog" "$tool" >&2
    exit 1
  fi
done

if [[ $# -gt 1 ]]; then
  printf '%s: usage: %s [train]\n' "$prog" "$prog" >&2
  exit 2
fi

# Resolved before anything is started, so a missing train fails immediately
# with choochoo's own message rather than after spawning half a train.
train_json=$(choo show --json "$@")
choo_status=$?
if ((choo_status != 0)); then
  exit "$choo_status"
fi
train_name=$(printf '%s' "$train_json" |
  node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>process.stdout.write(JSON.parse(s).name))')

connection_file=$(mktemp "${TMPDIR:-/tmp}/difit-train.XXXXXX")
printf '%s' "$train_json" | node "$router" >"$connection_file" 2>&1 &
router_pid=$!

# The router boots one difit per branch before it listens, so how long that
# takes scales with the train. Rather than guess a total, give up only once it
# has gone quiet: it reports every instance as that instance comes up.
idle=0
last_size=0
router_port=
while [[ -z $router_port ]]; do
  router_port=$(sed -n \
    's/.*server started on http:\/\/[^:]*:\([0-9][0-9]*\).*/\1/p' \
    "$connection_file")
  if ! kill -0 "$router_pid" >/dev/null 2>&1; then
    cat "$connection_file"
    wait "$router_pid"
    exit $?
  fi
  size=$(wc -c <"$connection_file")
  if ((size != last_size)); then
    last_size=$size
    idle=0
  elif ((idle >= 450)); then
    cat "$connection_file" >&2
    printf '%s: gave up waiting for the router to start\n' "$prog" >&2
    exit 1
  else
    idle=$((idle + 1))
  fi
  sleep 0.1
done

cat "$connection_file"
highway_tunnel_start "$router_port" "train ${train_name:-?}" \
  "difit-train-${train_name:-unknown}"

highway_tunnel_wait
exit $?
