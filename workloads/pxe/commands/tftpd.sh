#!/bin/bash
# shellcheck source-path=../../../
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

main() {
  source "$PKGROOT/lib/common.sh"
  info "Starting tftpd"
  exec /usr/sbin/in.tftpd --foreground \
  --user tftp \
  --address :69 \
  --secure /tftp
}

main "$@"
