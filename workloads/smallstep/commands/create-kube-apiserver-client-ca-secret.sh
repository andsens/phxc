#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")
source "$PKGROOT/lib/common.sh"

: "${NAMESPACE:?}"

main() {
  local cert_path=$1
  cert=$(cat "$cert_path")
  if [[ $(kubectl get -n "$NAMESPACE" secret kube-apiserver-client-ca -o jsonpath='{.data.tls\.crt}' | base64 -d) != "$cert" ]]; then
    info "kube-apiserver client CA secret validation failed, (re-)creating now"
    kubectl delete -n "$NAMESPACE" secret kube-apiserver-client-ca 2>/dev/null || true
    kubectl create -n "$NAMESPACE" secret generic kube-apiserver-client-ca --from-file=tls.crt="$cert_path"
  else
    info "kube-apiserver client CA secret validation succeeded"
  fi
}

main "$@"
