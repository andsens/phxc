#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit

main() {
  local addr_json prefixlen subnet network netmask
  addr_json=$(ip --json a | jq --arg host_ip "$HOST_IP" '.[] | select(.ifname!="lo") | .addr_info[] | select(.local==$host_ip)')
  prefixlen=$(jq -re '.prefixlen' <<<"$addr_json")
  subnet=$(subnetcalc "$HOST_IP/$prefixlen")
  network=$(grep 'Network' <<<"$subnet" | cut -d= -f2 | cut -d/ -f1 | tr -d ' ')
  netmask=$(grep 'Netmask' <<<"$subnet" | cut -d= -f2 | tr -d ' ')
  export DHCP_RANGE=$network,proxy,$netmask
  exec /usr/sbin/dnsmasq --conf-file=<(envsubst </etc/dnsmasq.conf)
}

main "$@"
