#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")
apk add -q jq kubectl gettext whois py3-virtualenv apache2-utils
virtualenv -q /usr/local/lib/yq
/usr/local/lib/yq/bin/pip3 install yq
ln -s /usr/local/lib/yq/bin/yq /usr/local/bin/yq

source "$PKGROOT/lib/common.sh"

main() {
  info "(Re-)creating coredns-custom configmap"
  export WAN_IPV4 DOMAIN K8SMASTER_IPV4 K8SMASTER_IPV6 ETCD_IPV4 ETCD_IPV6
  WAN_IPV4=$(get_setting cluster.wanIPv4)
  DOMAIN=$(get_setting cluster.domain)
  K8SMASTER_IPV4=$(get_setting machines.k8sMaster.fixedIPv4)
  K8SMASTER_IPV6=$(get_setting machines.k8sMaster.fixedIPv6)
  ETCD_IPV4=$(get_setting cluster.etcd.fixedIPv4)
  ETCD_IPV6=$(get_setting cluster.etcd.fixedIPv6)
  local file
  for file in /var/lib/home-cluster/config/coredns/*; do
    # shellcheck disable=SC2016
    envsubst '${WAN_IPV4} ${DOMAIN} ${K8SMASTER_IPV4} ${K8SMASTER_IPV6} ${ETCD_IPV4} ${ETCD_IPV6}' \
      <"$file" >"/config/$(basename "$file")"
  done
  kubectl delete -n "$NAMESPACE" configmap coredns-custom 2>/dev/null || true
  kubectl create -n kube-system configmap coredns-custom --from-file=/config
  info "Restarting CoreDNS"
  kubectl -n kube-system rollout restart deployment coredns
}

main "$@"
