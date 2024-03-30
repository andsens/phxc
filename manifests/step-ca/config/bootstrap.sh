#!/bin/bash
set -eo pipefail; shopt -s inherit_errexit

main() {
  : "${CLUSTER_NAME:?}"
  : "${STEPPATH:?}"
  : "${NAMESPACE:?}"
  local root_ca_crt intermediate_ca_crt
  root_ca_crt=$(kubectl get -n "$NAMESPACE" secret step-ca-certificates -o jsonpath='{.data.root_ca\.crt}' || true)
  intermediate_ca_crt=$(kubectl get -n "$NAMESPACE" secret step-ca-certificates -o jsonpath='{.data.intermediate_ca\.crt}' || true)
  if [[ -z "$root_ca_crt" || -z "$intermediate_ca_crt" ]]; then
    if [[ -z "$root_ca_crt" ]]; then
      step certificate create --profile=root-ca \
        --no-password --insecure \
        --curve=Ed25519 --kty=OKP --not-after=87600h \
        "$CLUSTER_NAME Root" "$STEPPATH/certs/root_ca.crt" "$STEPPATH/certs/root_ca.key"
    fi
    step certificate create --profile=intermediate-ca \
      --no-password --insecure \
      --curve=Ed25519 --kty=OKP --not-after=87600h \
      --ca="$STEPPATH/certs/root_ca.crt" --ca-key="$STEPPATH/certs/root_ca.key" \
      "$CLUSTER_NAME Intermediate" "$STEPPATH/certs/intermediate_ca.crt" "$STEPPATH/certs/intermediate_ca.key"
    kubectl create -n "$NAMESPACE" secret generic step-ca-certificates \
      --from-file="$STEPPATH/certs/root_ca.crt" \
      --from-file="$STEPPATH/certs/root_ca.key" \
      --from-file="$STEPPATH/certs/intermediate_ca.crt" \
      --from-file="$STEPPATH/certs/intermediate_ca.key"
  fi
}

main "$@"
