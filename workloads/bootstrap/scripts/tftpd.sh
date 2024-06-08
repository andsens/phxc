#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

CONFIG_TPL=/config/autoexec.ipxe
CONFIG=/tftp/config/autoexec.ipxe

main() {
  # shellcheck disable=SC1091
  source "$PKGROOT/.upkg/records.sh/records.sh"

  # shellcheck disable=SC2016
  envsubst '${CLUSTER_BOOTSERVER_FIXEDIPV4}' <$CONFIG_TPL >$CONFIG
  info "Starting tftpd"
  exec /usr/sbin/in.tftpd --foreground \
  --user tftp \
  --address :69 \
  --map-file /config/map-file \
  --secure /tftp
}

main "$@"
