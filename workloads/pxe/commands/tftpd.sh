#!/bin/bash
# shellcheck source-path=../../../
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

MAP_FILE=/var/lib/home-cluster/workloads/pxe/config/tftpd-mapfile

main() {
  source "$PKGROOT/lib/common.sh"

  trap 'set +e; info "Shutting down"; kill $TFTP_PID; exit 0' INT TERM EXIT ERR
  tftpd & TFTP_PID=$!
  local shasum
  shasum=$(sha1sum $MAP_FILE)
  while [[ -e /proc/$TFTP_PID ]]; do
    sleep 5
    if [[ $shasum != $(sha1sum $MAP_FILE) ]]; then
      shasum=$(sha1sum $MAP_FILE)
      info "Config changed"
      kill -TERM $TFTP_PID
      wait $TFTP_PID
      info "Stopped tftpd"
      tftpd & TFTP_PID=$!
    fi
  done
}

tftpd() {
  info "Starting tftpd"
  exec /usr/sbin/in.tftpd --foreground \
  --user tftp \
  --address :69 \
  --map-file $MAP_FILE \
  --secure /tftp
}

main "$@"
