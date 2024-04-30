#!/bin/bash
set -Eeo pipefail

: "${PKI_NAME:?}" "${STEPPATH:?}" "${NAMESPACE:?}"
ROOT_KEY_PATH=$STEPPATH/persistent-certs/root_ca_key
ROOT_CRT_PATH=$STEPPATH/persistent-certs/root_ca.crt
INTERMEDIATE_KEY_PATH=$STEPPATH/persistent-certs/intermediate_ca_key
INTERMEDIATE_CRT_PATH=$STEPPATH/persistent-certs/intermediate_ca.crt
KUBE_CLIENT_CA_KEY_PATH=$STEPPATH/persistent-certs/kube_apiserver_client_ca_key
KUBE_CLIENT_CA_CRT_PATH=$STEPPATH/persistent-certs/kube_apiserver_client_ca.crt

main() {
  create_certificates
  create_secrets
}

create_certificates() {
  info "Setting up root and intermediate certificates"

  if [[ ! -e $ROOT_KEY_PATH ]] || \
          step certificate needs-renewal "$ROOT_CRT_PATH"; then
    info "Root CA validation failed, (re-)creating now"
    step certificate create --profile=root-ca \
      --force --no-password --insecure \
      --not-after=87600h \
      "$PKI_NAME Root" "$ROOT_CRT_PATH" "$ROOT_KEY_PATH"
  else
    info "Root CA validation succeeded"
  fi

  if [[ ! -e $INTERMEDIATE_KEY_PATH ]] || \
        ! step certificate verify "$INTERMEDIATE_CRT_PATH" --roots="$ROOT_CRT_PATH" || \
          step certificate needs-renewal "$INTERMEDIATE_CRT_PATH"; then
    info "Intermediate CA validation failed, (re-)creating now"
    step certificate create --profile=intermediate-ca \
      --force --no-password --insecure \
      --not-after=87600h \
      --ca="$ROOT_CRT_PATH" --ca-key="$ROOT_KEY_PATH" \
      "$PKI_NAME" "$INTERMEDIATE_CRT_PATH" "$INTERMEDIATE_KEY_PATH"
  else
    info "Intermediate CA validation succeeded"
  fi

  if [[ ! -e $KUBE_CLIENT_CA_KEY_PATH ]] || \
        ! step certificate verify "$KUBE_CLIENT_CA_CRT_PATH" --roots="$ROOT_CRT_PATH" || \
          step certificate needs-renewal "$INTERMEDIATE_CRT_PATH"; then
    info "kube-apiserver client CA validation failed, (re-)creating now"
    step certificate create --profile=intermediate-ca \
      --force --no-password --insecure \
      --not-after=87600h \
      --ca="$ROOT_CRT_PATH" --ca-key="$ROOT_KEY_PATH" \
      "$PKI_NAME Kubernetes Client CA" "$KUBE_CLIENT_CA_CRT_PATH" "$KUBE_CLIENT_CA_KEY_PATH"
  else
    info "kube-apiserver client CA validation succeeded"
  fi
}

create_secrets() {
  info "Creating smallstep certificate chain secrets"

  if [[ $(kubectl get -n "$NAMESPACE" secret smallstep-root -o jsonpath='{.data.tls\.crt}' | base64 -d) != $(cat "$ROOT_CRT_PATH") ]]; then
    info "Root CA secret validation failed, (re-)creating now"
    kubectl delete -n "$NAMESPACE" secret smallstep-root 2>/dev/null || true
    kubectl create -n "$NAMESPACE" secret generic smallstep-root --from-file=tls.crt="$ROOT_CRT_PATH"
  else
    info "Root CA secret validation succeeded"
  fi

  if [[ $(kubectl get -n "$NAMESPACE" secret smallstep-intermediate -o jsonpath='{.data.tls\.crt}' | base64 -d) != $(cat "$INTERMEDIATE_CRT_PATH") ]]; then
    info "Intermediate CA secret validation failed, (re-)creating now"
    kubectl delete -n "$NAMESPACE" secret smallstep-intermediate 2>/dev/null || true
    kubectl create -n "$NAMESPACE" secret tls smallstep-intermediate --cert="$INTERMEDIATE_CRT_PATH" --key="$INTERMEDIATE_KEY_PATH"
  else
    info "Intermediate CA secret validation succeeded"
  fi

  if [[ $(kubectl get -n "$NAMESPACE" secret kube-apiserver-client-ca -o jsonpath='{.data.tls\.crt}' | base64 -d) != $(cat "$KUBE_CLIENT_CA_CRT_PATH") ]]; then
    info "kube-apiserver client CA secret validation failed, (re-)creating now"
    kubectl delete -n "$NAMESPACE" secret kube-apiserver-client-ca 2>/dev/null || true
    kubectl create -n "$NAMESPACE" secret tls kube-apiserver-client-ca --cert="$KUBE_CLIENT_CA_CRT_PATH" --key="$KUBE_CLIENT_CA_KEY_PATH"
  else
    info "kube-apiserver client CA secret validation succeeded"
  fi
}

info() {
  local tpl=$1; shift
  # shellcheck disable=2059
  printf "%s: $tpl\n" "$(basename "$0")" "$@" >&2
}

main "$@"
