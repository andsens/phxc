#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
source "$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")/lib/resource-ready.sh"
is_ready() {
  statefulset_ready smallstep step-ca
  statefulset_ready smallstep kube-apiserver-client-ca
  deployment_ready smallstep step-issuer
  endpoint_ready smallstep kube-apiserver-client-ca-host
  endpoint_ready smallstep step-ca
}
check_ready "$@"
