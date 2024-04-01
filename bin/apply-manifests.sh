#!/usr/bin/env bash
# shellcheck source-path=../
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"

  DOC="apply-manifests.sh - Apply all manifests to the cluster
Usage:
  apply-manifests.sh
"
# docopt parser below, refresh this parser with `docopt.sh apply-manifests.sh`
# shellcheck disable=2016,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:83}; usage=${DOC:56:27}; digest=eb41d; shorts=(); longs=()
argcounts=(); node_0(){ required ; }; node_1(){ required 0; }
cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:56:27}" >&2; exit 1; }'; unset ; parse 1 "$@"; return 0
local prefix=${DOCOPT_PREFIX:-''}; unset ; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p ; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' apply-manifests.sh`
  eval "$(docopt "$@")"

  local notified=false max_wait=300 wait_left=300
  while [[ ! $(kubectl get -n kube-system deployment cilium-operator -ojsonpath='{.status.readyReplicas}' 2>&1) != 1 ]]; do
    $notified || info "cilium is not ready yet..."
    notified=true
    sleep 1
    ((--wait_left > 0)) || fatal "Timed out after %d seconds for cilium to become ready." "$((max_wait / 60))"
  done

  "$PKGROOT/manifests/networkpolicies/apply.sh"
  "$PKGROOT/manifests/csi-driver-nfs/apply.sh"
  "$PKGROOT/manifests/kubernetes-secret-generator/apply.sh"
  "$PKGROOT/manifests/cert-manager/apply.sh"
  "$PKGROOT/manifests/cert-manager-issuers/apply.sh"
  "$PKGROOT/manifests/step-ca/apply.sh"
  "$PKGROOT/manifests/redis/apply.sh"
  "$PKGROOT/manifests/docker-registry/apply.sh"
}

main "$@"
