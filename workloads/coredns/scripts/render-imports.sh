#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

main() {
  [[ $# -le 1 ]] || usage
  [[ $# -eq 0 || $1 = '--watch' ]] || usage
  local imports=/etc/coredns/imports apiserver_ips apiserver_ip
  # shellcheck disable=SC2206
  IFS=, apiserver_ips=($HOST_IPS)
  rm -f $imports/kube-apiserver-ipv6.conf $imports/kube-apiserver-ipv4.conf
  for apiserver_ip in "${apiserver_ips[@]}"; do

    # shellcheck disable=SC2016
    [[ -e $imports/kube-apiserver-ipv4.conf ]] || \
    printf 'template IN A api.{$CLUSTER_DOMAIN}. {
        answer "api.{$CLUSTER_DOMAIN}. 60 IN A %s"
    }\n' "$apiserver_ip" >$imports/kube-apiserver-ipv4.conf

    # shellcheck disable=SC2016
    [[ -e $imports/kube-apiserver-ipv6.conf ]] || \
    printf 'template IN AAAA api.{$CLUSTER_DOMAIN}. {
        answer "api.{$CLUSTER_DOMAIN}. 60 IN A %s"
    }\n' "$apiserver_ip" >$imports/kube-apiserver-ipv6.conf

  done

  trap 'kill -TERM $SLEEP_PID' TERM
  local external_ip
  while true; do
    if external_ip=$(curl -sf https://api.ipify.org/); then
      printf 'template IN A . {
          answer "{{.Name}} 60 IN A %s"
      }\n' "$external_ip" >$imports/wan-ip.conf
    else
      printf "Failed retrieving WAN IP\n" >&2
    fi
    [[ $1 = '--watch' ]] || break
    sleep 60 & SLEEP_PID=$1
    wait || break
  done
}

usage() {
  printf "Usage: render-imports.sh [--watch]\n" >&2
  return 1
}

main "$@"
