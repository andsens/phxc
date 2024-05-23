#!/bin/bash
# shellcheck source-path=../../../
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

CONFIG=/var/lib/home-cluster/workloads/pxe/config/nbd-server.conf

main() {
  source "$PKGROOT/lib/common.sh"

  trap 'set +e; info "Shutting down"; kill $NBD_PID; exit 0' INT TERM EXIT ERR
  nbd-server -C $CONFIG -p /var/run/nbd-server.pid
  local max_wait=50 wait_left=50
  until NBD_PID=$(cat /var/run/nbd-server.pid 2>/dev/null); do
    sleep .1
    ((--wait_left > 0)) || fatal "Timed out after %d seconds waiting nbd-server to become ready." "$((max_wait / 10))"
  done
  info "nbd-server started"
  local shasum
  shasum=$(sha1sum $CONFIG)
  while [[ -e /proc/$NBD_PID ]]; do
    sleep 5
    if [[ $shasum != $(sha1sum $CONFIG) ]]; then
      shasum=$(sha1sum $CONFIG)
      info "Config changed, signaling nbd-server"
      kill -HUP "$NBD_PID"
    fi
  done
  info "nbd-server crashed"
}

main "$@"
