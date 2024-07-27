#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=/usr/local/lib/upkg

main() {
  source "$PKGROOT/.upkg/bgpid/bgpid.sh"
  trap "bg_killall" HUP INT TERM EXIT
  local filter_if
  filter_if=$(ip -o a | grep "${HOST_IP:?}" | head -n1 | cut -d ' ' -f 2)
  bg_run tcpdump -Z nobody -i "$filter_if" -nl port 69 and udp
  bg_run /usr/sbin/in.tftpd --foreground --user tftp --address :69 --map-file /config/map-file --secure /tftp --blocksize 1468
  bg_block
}

main "$@"
