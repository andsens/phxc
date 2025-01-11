#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
source "$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")/lib/resource-ready.sh"
is_ready() {
  statefulset_ready smallstep kube-client-ca
  statefulset_ready smallstep kube-server-ca
  deployment_ready smallstep kube-server-issuer
  endpoint_ready smallstep kube-client-ca-host
  endpoint_ready smallstep kube-server-ca
  curl -sfk https://kube-server-ca.smallstep.svc.cluster.local:9000/health &>/dev/null
}
check_ready "$@"
