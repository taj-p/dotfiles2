#!/usr/bin/env bash

# Shared Highway-tunnel plumbing for the difit wrappers. Sourced, never run:
# `difit-highway.sh` points it at one difit server, `difit-train.sh` points it
# at the router in front of a whole train's worth of them. Both want the same
# thing — one cached tunnel, its output replayed to the terminal, and its URL
# published to the llm-watch dashboard for as long as it lives.
#
# Caller contract:
#   prog=<name used in messages>
#   highway_link_path=<path appended to the published URL>   # optional
#   highway_tunnel_start <port> <link-title> [link-id]
#   highway_tunnel_wait                       # blocks; $? is the tunnel's status
#   highway_tunnel_cleanup                    # from the caller's EXIT trap
#
# The caller keeps ownership of whatever it put on that port: this file knows
# nothing about difit, so a wrapper's own cleanup still has to kill its server.

highway_pid=
highway_log=
publisher_pid=
printer_pid=
highway_link_kind=difit
highway_link_id=

# Withdraws the dashboard link and stops the helper that maintains it.
highway_tunnel_unpublish() {
  if [[ -n $publisher_pid ]] && kill -0 "$publisher_pid" >/dev/null 2>&1; then
    kill "$publisher_pid" >/dev/null 2>&1 || true
    wait "$publisher_pid" 2>/dev/null || true
  fi
  publisher_pid=
  if command -v llm-watch >/dev/null 2>&1; then
    # Only clear the id this run published, so a sibling wrapper's link
    # survives. With no id, llm-watch clears the kind's default id — which is
    # what the single-difit wrapper has always done.
    if [[ -n $highway_link_id ]]; then
      llm-watch link clear --kind "$highway_link_kind" --id "$highway_link_id" \
        >/dev/null 2>&1 || true
    else
      llm-watch link clear --kind "$highway_link_kind" >/dev/null 2>&1 || true
    fi
  fi
}

highway_tunnel_cleanup() {
  highway_tunnel_unpublish
  if [[ -n $printer_pid ]] && kill -0 "$printer_pid" >/dev/null 2>&1; then
    kill "$printer_pid" >/dev/null 2>&1 || true
    wait "$printer_pid" 2>/dev/null || true
  fi
  printer_pid=
  if [[ -n $highway_pid ]] && kill -0 "$highway_pid" >/dev/null 2>&1; then
    kill "$highway_pid" >/dev/null 2>&1 || true
    wait "$highway_pid" 2>/dev/null || true
  fi
  highway_pid=
  if [[ -n $highway_log ]]; then
    rm -f "$highway_log"
    highway_log=
  fi
}

# Starts the tunnel for $1, titles the dashboard link $2, and publishes it
# under the optional stable id $3.
highway_tunnel_start() {
  local port=$1 link_title=$2 link_id=${3:-}
  highway_link_id=$link_id

  printf '%s: starting the cached Highway tunnel for localhost:%s\n' \
    "$prog" "$port"

  # Highway's output is captured so the tunnel URL can be published to the
  # llm-watch dashboard, and replayed to the terminal so nothing is hidden.
  highway_log=$(mktemp "${TMPDIR:-/tmp}/${prog}-log.XXXXXX")
  infra highway http "$port" >"$highway_log" 2>&1 &
  highway_pid=$!

  tail -n +1 -f "$highway_log" 2>/dev/null &
  printer_pid=$!

  if command -v llm-watch >/dev/null 2>&1; then
    highway_tunnel_publish "$link_title" "$link_id" &
    publisher_pid=$!
  fi
}

# Waits for the tunnel URL to appear in the log, then keeps the dashboard link
# alive for as long as the tunnel runs. Runs as a background subshell.
highway_tunnel_publish() {
  local link_title=$1 link_id=$2 tunnel_url= _
  local -a id_args=()
  if [[ -n $link_id ]]; then
    id_args=(--id "$link_id")
  fi
  for _ in $(seq 1 300); do
    # Strip ANSI colour before matching so the URL is found either way.
    tunnel_url=$(sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$highway_log" |
      grep -oE 'https://[A-Za-z0-9._-]+\.highway\.[A-Za-z0-9.-]+' |
      head -n 1)
    if [[ -n $tunnel_url ]]; then
      break
    fi
    if ! kill -0 "$highway_pid" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  if [[ -z $tunnel_url ]]; then
    printf '%s: could not detect the tunnel URL; dashboard link skipped\n' \
      "$prog" >&2
    return 0
  fi
  printf '%s: dashboard link %s%s\n' "$prog" "$tunnel_url" "${highway_link_path:-}"
  # Re-published on a heartbeat: llm-watch expires a link that stops being
  # refreshed, so a killed tunnel cannot leave a dead URL on the dashboard.
  while kill -0 "$highway_pid" >/dev/null 2>&1; do
    llm-watch link set --kind "$highway_link_kind" "${id_args[@]}" \
      --url "$tunnel_url${highway_link_path:-}" --title "$link_title" \
      >/dev/null 2>&1 || true
    sleep 60
  done
}

# Blocks until the tunnel exits, then withdraws the dashboard link. Returns
# the tunnel's exit status so the caller can exit with it.
highway_tunnel_wait() {
  local status=0
  wait "$highway_pid" || status=$?
  highway_pid=
  highway_tunnel_unpublish
  return "$status"
}
