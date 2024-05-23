#!/bin/bash
# shellcheck source-path=../../../
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

main() {
  source "$PKGROOT/lib/common.sh"
  nbd-server -C /var/lib/home-cluster/workloads/pxe/config/nbd-server.conf -p /var/run/nbd-server.pid
  local max_wait=50 wait_left=50
  until PID=$(cat /var/run/nbd-server.pid 2>/dev/null); do
    sleep .1
    ((--wait_left > 0)) || fatal "Timed out after %d seconds waiting nbd-server to become ready." "$((max_wait / 10))"
  done
  info "nbd-server started"
  # shellcheck disable=SC2064
  trap 'set +e; info "Shutting down"; kill $PID; exit 0' INT HUP TERM EXIT
  local interval=0
  while [[ -e /proc/$PID ]]; do
    sleep $interval
    [[ $interval -ge 60 ]] || interval=$(( interval + 5 ))
  done
  info "nbd-server crashed"
}

main "$@"
