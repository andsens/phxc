#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit

: "${NAMESPACE:?}"

# Must be dependencyless, because it is called from docker-registry setup as well

main() {
  local cert_path=$1
  cert=$(cat "$cert_path")
  if [[ $(kubectl get -n "$NAMESPACE" secret kube-apiserver-client-ca -o jsonpath='{.data.tls\.crt}' | base64 -d) != "$cert" ]]; then
    printf "create-kube-apiserver-client-ca-secret.sh: kube-apiserver client CA secret validation failed, (re-)creating now" >&2
    kubectl delete -n "$NAMESPACE" secret kube-apiserver-client-ca 2>/dev/null || true
    kubectl create -n "$NAMESPACE" secret generic kube-apiserver-client-ca --from-file=tls.crt="$cert_path"
  else
    printf "create-kube-apiserver-client-ca-secret.sh: kube-apiserver client CA secret validation succeeded" >&2
  fi
}

main "$@"
