#!/bin/bash
set -eo pipefail; shopt -s inherit_errexit

main() {
  : "${CLUSTER_NAME:?}" "${STEPPATH:?}" "${NAMESPACE:?}"
  setup_certificates
  setup_issuer_provisioner
}

setup_certificates() {
  local root_ca_is_new=false
  printf "bootstrap.sh: Setting up root and intermediate certificates\n" >&2

  mkdir "$STEPPATH/certs/root"
  if ! kubectl get -n "$NAMESPACE" secret step-ca-root -o jsonpath='{.data.tls\.crt}' | base64 -d >"$STEPPATH/certs/root/tls.crt"; then
    printf "bootstrap.sh: Root certificate does not exist, creating now\n" >&2
    rm -f "$STEPPATH/certs/root/tls.crt"
    root_ca_is_new=true
    step certificate create --profile=root-ca \
      --no-password --insecure \
      --not-after=87600h \
      "$CLUSTER_NAME Root" "$STEPPATH/certs/root/tls.crt" "$STEPPATH/certs/root/tls.key"
    kubectl create -n "$NAMESPACE" secret tls step-ca-root \
      --cert="$STEPPATH/certs/root/tls.crt" \
      --key="$STEPPATH/certs/root/tls.key"
  else
    printf "bootstrap.sh: Root certificate exists, skipping creation\n" >&2
  fi

  if $root_ca_is_new || ! kubectl get -n "$NAMESPACE" secret step-ca-intermediate >/dev/null; then
    printf "bootstrap.sh: Intermediate certificate does not exist or the root has been recreated, creating now\n" >&2
    mkdir "$STEPPATH/certs/intermediate"
    step certificate create --profile=intermediate-ca \
      --no-password --insecure \
      --not-after=87600h \
      --ca="$STEPPATH/certs/root/tls.crt" --ca-key="$STEPPATH/certs/root/tls.key" \
      "$CLUSTER_NAME Intermediate" "$STEPPATH/certs/intermediate/tls.crt" "$STEPPATH/certs/intermediate/tls.key"
    kubectl create -n "$NAMESPACE" secret tls step-ca-intermediate \
      --cert="$STEPPATH/certs/intermediate/tls.crt" \
      --key="$STEPPATH/certs/intermediate/tls.key" || \
    kubectl replace -n "$NAMESPACE" secret tls step-ca-intermediate \
      --cert="$STEPPATH/certs/intermediate/tls.crt" \
      --key="$STEPPATH/certs/intermediate/tls.key"
  else
    printf "bootstrap.sh: Intermediate certificate exists, skipping creation\n" >&2
  fi
}

setup_issuer_provisioner() {
  printf "bootstrap.sh: Setting up step issuer provisioner\n" >&2
  local jwk_is_new=false

  mkdir "$STEPPATH/certs/issuer-provisioner"
  if ! kubectl get -n "$NAMESPACE" secret step-ca-issuer-provisioner -o jsonpath='{.data.pub\.json}' | base64 -d >"$STEPPATH/certs/issuer-provisioner/pub.json"; then
    printf "bootstrap.sh: step-issuer provisioner JWK does not exist, creating now\n" >&2
    rm -f "$STEPPATH/certs/issuer-provisioner/pub.json"
    step crypto jwk create \
      --password-file="$STEPPATH/issuer-provisioner-password/password" \
      --use sig \
      "$STEPPATH/certs/issuer-provisioner/pub.json" "$STEPPATH/certs/issuer-provisioner/priv.json"
    kubectl create -n "$NAMESPACE" secret generic step-ca-issuer-provisioner \
      --from-file="$STEPPATH/certs/issuer-provisioner/pub.json" \
      --from-file="$STEPPATH/certs/issuer-provisioner/priv.json"
  else
    printf "bootstrap.sh: step-issuer provisioner JWK exists, skipping creation\n" >&2
  fi

  if $jwk_is_new || ! kubectl get stepclusterissuer step-issuer >/dev/null; then
    printf "bootstrap.sh: StepClusterIssuer does not exist or the provisioner JWK has been recreated, creating now\n" >&2
    kubectl apply -f <(printf -- "apiVersion: certmanager.step.sm/v1beta1
kind: StepClusterIssuer
metadata:
  name: step-issuer
spec:
  url: https://step-ca.step-ca.svc.cluster.local:9000
  caBundle: %s
  provisioner:
    name: step-issuer
    kid: %s
    passwordRef:
      namespace: step-ca
      name: step-ca-issuer-provisioner-password
      key: password" "$(base64 -w0 "$STEPPATH/certs/root/tls.crt")" "$(step crypto jwk thumbprint < "$STEPPATH/certs/issuer-provisioner/pub.json")"
    )
  else
    printf "bootstrap.sh: StepClusterIssuer exists, skipping creation\n" >&2
  fi
}

main "$@"
