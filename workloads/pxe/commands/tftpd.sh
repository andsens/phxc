#!/bin/bash
# shellcheck source-path=../../../
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

CONFIG_TPL=/var/lib/home-cluster/workloads/pxe/config/autoexec.ipxe
CONFIG=/tftp/config/autoexec.ipxe

main() {
  source "$PKGROOT/lib/common.sh"

  # shellcheck disable=SC2016
  envsubst '${CLUSTER_BOOTSERVER_FIXEDIPV4}' <$CONFIG_TPL >$CONFIG
  info "Starting tftpd"
  exec /usr/sbin/in.tftpd --foreground \
  --user tftp \
  --address :69 \
  --map-file /var/lib/home-cluster/workloads/pxe/config/map-file \
  --secure /tftp
}

main "$@"
