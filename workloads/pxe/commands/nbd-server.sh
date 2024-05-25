#!/bin/bash
# shellcheck source-path=../../../
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

BASE_CONFIG=/var/lib/home-cluster/workloads/pxe/config/nbd-server.conf
CONFIG=/etc/nbd-server/config

main() {
  source "$PKGROOT/lib/common.sh"

  generate_config >$CONFIG
  trap 'set +e; info "Shutting down"; kill $NBD_PID; exit 0' INT TERM EXIT ERR
  nbd-server -p /var/run/nbd-server.pid
  local max_wait=50 wait_left=50
  until NBD_PID=$(cat /var/run/nbd-server.pid 2>/dev/null); do
    sleep .1
    ((--wait_left > 0)) || fatal "Timed out after %d seconds waiting nbd-server to become ready." "$((max_wait / 10))"
  done
  info "nbd-server started"
  local config
  while [[ -e /proc/$NBD_PID ]]; do
    config=$(generate_config)
    sleep 10
    if ! diff -q <(printf "%s\n" "$config") $CONFIG 2>/dev/null; then
      printf "%s\n" "$config" >$CONFIG
      info "Config changed, signaling nbd-server"
      kill -HUP "$NBD_PID"
    fi
  done
  info "nbd-server crashed"
}

generate_config() {
  cat $BASE_CONFIG
  local img exportname
  for img in /images/squashfs/*.img; do
    exportname=$(basename "$img" .img)
    printf "[%s]\n  exportname = %s\n  readonly = true\n" "$exportname" "$img"
  done
}

main "$@"
