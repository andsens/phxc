#!/bin/bash
set -Eeo pipefail

main() {
  : "${CLUSTER_NAME:?}" "${STEPPATH:?}" "${NAMESPACE:?}"
  setup_certificates
  setup_issuer_provisioner
  setup_ssh_host_provisioner
}

setup_certificates() {
  printf "bootstrap.sh: Setting up root and intermediate certificates\n" >&2

  local root_ca_is_new=false
  if [[ ! -e "$STEPPATH/certs/root/tls.key" ]]; then
    rm -f "$STEPPATH/certs/root/tls.crt"
    printf "bootstrap.sh: Root certificate does not exist on PV, creating now\n" >&2
    root_ca_is_new=true
    step certificate create --profile=root-ca \
      --no-password --insecure \
      --not-after=87600h \
      "$CLUSTER_NAME Root" "$STEPPATH/certs/root/tls.crt" "$STEPPATH/certs/root/tls.key"
  else
    printf "bootstrap.sh: Root certificate exists on PV, skipping creation\n" >&2
  fi

  if $root_ca_is_new || ! kubectl get -n "$NAMESPACE" secret smallstep-root -o jsonpath='{.data.tls\.crt}' >/dev/null; then
    printf "bootstrap.sh: Root certificate secret does not exist or has been recreated, creating now\n" >&2
    kubectl create -n "$NAMESPACE" secret tls smallstep-root \
      --cert="$STEPPATH/certs/root/tls.crt" \
      --key="$STEPPATH/certs/root/tls.key" || \
    kubectl replace -n "$NAMESPACE" secret tls smallstep-root \
      --cert="$STEPPATH/certs/root/tls.crt" \
      --key="$STEPPATH/certs/root/tls.key"
  else
    printf "bootstrap.sh: Root certificate secret exists, skipping creation\n" >&2
  fi

  if $root_ca_is_new || ! kubectl get -n "$NAMESPACE" secret smallstep-intermediate >/dev/null; then
    printf "bootstrap.sh: Intermediate certificate does not exist or the root has been recreated, creating now\n" >&2
    mkdir "$STEPPATH/certs/intermediate"
    step certificate create --profile=intermediate-ca \
      --no-password --insecure \
      --not-after=87600h \
      --ca="$STEPPATH/certs/root/tls.crt" --ca-key="$STEPPATH/certs/root/tls.key" \
      "$CLUSTER_NAME Intermediate" "$STEPPATH/certs/intermediate/tls.crt" "$STEPPATH/certs/intermediate/tls.key"
    kubectl create -n "$NAMESPACE" secret tls smallstep-intermediate \
      --cert="$STEPPATH/certs/intermediate/tls.crt" \
      --key="$STEPPATH/certs/intermediate/tls.key" || \
    kubectl replace -n "$NAMESPACE" secret tls smallstep-intermediate \
      --cert="$STEPPATH/certs/intermediate/tls.crt" \
      --key="$STEPPATH/certs/intermediate/tls.key"
  else
    printf "bootstrap.sh: Intermediate certificate exists, skipping creation\n" >&2
  fi
}

setup_issuer_provisioner() {
  printf "bootstrap.sh: Setting up step issuer provisioner\n" >&2
  local jwk_is_new=false

  mkdir "$STEPPATH/certs/step-issuer-provisioner"
  if ! kubectl get -n "$NAMESPACE" secret step-issuer-provisioner -o jsonpath='{.data.pub\.json}' | base64 -d >"$STEPPATH/certs/step-issuer-provisioner/pub.json"; then
    printf "bootstrap.sh: step-issuer provisioner JWK does not exist, creating now\n" >&2
    rm -f "$STEPPATH/certs/step-issuer-provisioner/pub.json"
    step crypto jwk create \
      --password-file="$STEPPATH/step-issuer-provisioner-password/password" \
      --use sig \
      "$STEPPATH/certs/step-issuer-provisioner/pub.json" "$STEPPATH/certs/step-issuer-provisioner/priv.json"
    kubectl create -n "$NAMESPACE" secret generic step-issuer-provisioner \
      --from-file="$STEPPATH/certs/step-issuer-provisioner/pub.json" \
      --from-file="$STEPPATH/certs/step-issuer-provisioner/priv.json"
  else
    printf "bootstrap.sh: step-issuer provisioner JWK exists, skipping creation\n" >&2
  fi

  kubectl get stepclusterissuer step-issuer -ojsonpath='{.spec.caBundle}' | base64 -d >"$STEPPATH/certs/step-issuer-provisioner/caBundle.key" || true
  if $jwk_is_new || ! diff -q "$STEPPATH/certs/root/tls.crt" "$STEPPATH/certs/step-issuer-provisioner/caBundle.key"; then
    printf "bootstrap.sh: StepClusterIssuer does not exist, the provisioner JWK has been recreated, or the caBundle is incorrect, creating now\n" >&2
    kubectl apply -f <(printf -- "apiVersion: certmanager.step.sm/v1beta1
kind: StepClusterIssuer
metadata:
  name: step-issuer
spec:
  url: https://step-ca.smallstep.svc.cluster.local:9000
  caBundle: %s
  provisioner:
    name: step-issuer
    kid: %s
    passwordRef:
      namespace: smallstep
      name: step-issuer-provisioner-password
      key: password" "$(base64 -w0 "$STEPPATH/certs/root/tls.crt")" "$(step crypto jwk thumbprint < "$STEPPATH/certs/step-issuer-provisioner/pub.json")"
    )
  else
    printf "bootstrap.sh: StepClusterIssuer exists, skipping creation\n" >&2
  fi
}

setup_ssh_host_provisioner() {
  printf "bootstrap.sh: Setting up SSH  provisioner\n" >&2
  local jwk_is_new=false

  mkdir "$STEPPATH/certs/ssh-host-provisioner"
  if ! kubectl get -n "$NAMESPACE" secret step-ssh-host-provisioner -o jsonpath='{.data.pub\.json}' | base64 -d >"$STEPPATH/certs/ssh-host-provisioner/pub.json"; then
    printf "bootstrap.sh: ssh-host-provisioner provisioner JWK does not exist, creating now\n" >&2
    rm -f "$STEPPATH/certs/ssh-host-provisioner/pub.json"
    step crypto jwk create \
      --password-file="$STEPPATH/ssh-host-provisioner-password/password" \
      --use sig \
      "$STEPPATH/certs/ssh-host-provisioner/pub.json" "$STEPPATH/certs/ssh-host-provisioner/priv.json"
    kubectl create -n "$NAMESPACE" secret generic step-ssh-host-provisioner \
      --from-file="$STEPPATH/certs/ssh-host-provisioner/pub.json" \
      --from-file="$STEPPATH/certs/ssh-host-provisioner/priv.json"
  else
    printf "bootstrap.sh: ssh-host provisioner JWK exists, skipping creation\n" >&2
  fi
}

main "$@"
