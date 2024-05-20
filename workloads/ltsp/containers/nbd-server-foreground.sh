#!/bin/bash
set -Eeo pipefail; shopt -s inherit_errexit

main() {
  nbd-server -r -C /src/nbd.conf -p /var/run/nbd-server.pid
  local max_wait=50 wait_left=50
  until [[ -e /var/run/nbd-server.pid ]]; do
    sleep .1
    ((--wait_left > 0)) || fatal "Timed out after %d seconds waiting nbd-server to become ready." "$((max_wait / 10))"
  done
  PID=$(cat /var/run/nbd-server.pid)
  # shellcheck disable=SC2064,SC2086
  if ps -o pid= -p $PID 2>/dev/null; then
    printf "nbd-server running\n" >&2
    trap "kill $PID" INT HUP TERM EXIT
    tail -f --pid "$PID" /dev/null & wait $!
  else
    printf "nbd-server crashed during startup\n" >&2
    return 1
  fi
}

main "$@"
