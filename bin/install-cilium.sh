#!/usr/bin/env bash
# shellcheck source-path=..
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
  source "$PKGROOT/lib/machine-id.sh"

  DOC="install-cilium - Install cilium in k3s
Usage:
  install-cilium
"
# docopt parser below, refresh this parser with `docopt.sh install-cilium.sh`
# shellcheck disable=2016,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:62}; usage=${DOC:39:23}; digest=014c6; shorts=(); longs=()
argcounts=(); node_0(){ required ; }; node_1(){ required 0; }
cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:39:23}" >&2; exit 1; }'; unset ; parse 1 "$@"; return 0
local prefix=${DOCOPT_PREFIX:-''}; unset ; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p ; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' install-cilium.sh`
  eval "$(docopt "$@")"
  source "$PKGROOT/vars.sh"
  confirm_machine_id k8s-nas

  local notified=false max_wait=300 wait_left=300
  while ! kubectl get -n kube-system deployment coredns -o name >/dev/null 2>&1; do
    $notified || info "k3s is not ready yet..."
    notified=true
    sleep 1
    ((--wait_left > 0)) || fatal "Timed out after %d seconds for cilium to become ready." "$((max_wait / 60))"
  done
  if ! kubectl get -n kube-system deployment cilium-operator -o name >/dev/null 2>&1; then
    info "Cilium is not installed, installing now"
    /usr/local/bin/cilium install --version=1.15.1 \
      --set=ipam.operator.clusterPoolIPv4PodCIDRList="$CLUSTER_IPV4_CIDR" \
      --set=ipam.operator.clusterPoolIPv6PodCIDRList="$CLUSTER_IPV6_CIDR" \
      --set=ipv6.enabled=true \
      --set=envoy.enabled=false \
      --set=hubble.enabled=false \
      --set=hubble.relay.gops.enabled=false \
      --set=kubeProxyReplacement=true \
      --set=encryption.enabled=true \
      --set=encryption.type=wireguard \
      --set=socketLB.enabled=true \
      --set=kubeConfigPath=/etc/rancher/k3s/k3s.yaml
  else
    info "Cilium is already installed"
  fi

  info "Waiting for Cilium to become ready"
  local max_wait=300 wait_left=300
  while [[ ! $(kubectl get -n kube-system deployment cilium-operator -ojsonpath='{.status.readyReplicas}' 2>&1) != 1 ]]; do
    sleep 1
    ((--wait_left > 0)) || fatal "Timed out after %d seconds waiting for Cilium to become ready" "$max_wait"
  done
  info "Cilium is ready"
}

main "$@"
