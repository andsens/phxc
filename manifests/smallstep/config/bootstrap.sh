#!/bin/bash
set -Eeo pipefail

: "${CLUSTER_NAME:?}" "${STEPPATH:?}" "${NAMESPACE:?}"
ROOT_KEY_PATH=$STEPPATH/persistent-certs/root_ca_key
ROOT_CRT_PATH=$STEPPATH/persistent-certs/root_ca.crt
INTERMEDIATE_KEY_PATH=$STEPPATH/persistent-certs/intermediate_ca_key
INTERMEDIATE_CRT_PATH=$STEPPATH/persistent-certs/intermediate_ca.crt
STEP_ISSUER_DIR=$STEPPATH/certs/step-issuer-provisioner
SSH_HOST_DIR=$STEPPATH/certs/ssh-host-provisioner

main() {
  create_certificates
  create_secrets
  setup_issuer_provisioner
  create_ssh_host_provisioner_key
}

create_certificates() {
  printf "bootstrap.sh: Setting up root and intermediate certificates\n" >&2

  if [[ ! -e "$ROOT_KEY_PATH" || ! -e "$INTERMEDIATE_KEY_PATH" ]]; then
    if [[ ! -e "$ROOT_KEY_PATH" ]]; then
      printf "bootstrap.sh: Root key does not exist on the PV, creating now\n" >&2
      rm -f "$ROOT_CRT_PATH"
      step certificate create --profile=root-ca \
        --no-password --insecure \
        --not-after=87600h \
        "$CLUSTER_NAME Root" "$ROOT_CRT_PATH" "$ROOT_KEY_PATH"
      printf "bootstrap.sh: Root key is new, creating new intermediate\n" >&2
    else
      printf "bootstrap.sh: Root key exists on the PV, skipping creation\n" >&2
      printf "bootstrap.sh: Intermediate key does not exist on the PV or root has been recreated, creating now\n" >&2
    fi
    rm -f "$INTERMEDIATE_KEY_PATH" "$INTERMEDIATE_CRT_PATH"
    step certificate create --profile=intermediate-ca \
      --no-password --insecure \
      --not-after=87600h \
      --ca="$ROOT_CRT_PATH" --ca-key="$ROOT_KEY_PATH" \
      "$CLUSTER_NAME Intermediate" "$INTERMEDIATE_CRT_PATH" "$INTERMEDIATE_KEY_PATH"
  else
    printf "bootstrap.sh: Root and intermediate keys exists on the PV, skipping creation\n" >&2
  fi
}

create_secrets() {
  if [[ $(kubectl get -n "$NAMESPACE" secret smallstep-root -o jsonpath='{.data.tls\.crt}' | base64 -d) != $(cat "$ROOT_CRT_PATH") ]]; then
    printf "bootstrap.sh: Root certificate secret does not exist or does not match the one on the PV, creating now\n" >&2
    kubectl delete -n "$NAMESPACE" secret smallstep-root 2>/dev/null || true
    kubectl create -n "$NAMESPACE" secret tls smallstep-root --cert="$ROOT_CRT_PATH" --key="$ROOT_KEY_PATH"
  else
    printf "bootstrap.sh: Root certificate secret exists and matches, skipping creation\n" >&2
  fi

  if [[ $(kubectl get -n "$NAMESPACE" secret smallstep-intermediate -o jsonpath='{.data.tls\.crt}' | base64 -d) != $(cat "$INTERMEDIATE_CRT_PATH") ]]; then
    printf "bootstrap.sh: Intermediate certificate secret does not exist or the root does not match the one on the PV, creating now\n" >&2
    kubectl delete -n "$NAMESPACE" secret smallstep-intermediate 2>/dev/null || true
    kubectl create -n "$NAMESPACE" secret tls smallstep-intermediate --cert="$INTERMEDIATE_CRT_PATH" --key="$INTERMEDIATE_KEY_PATH"
  else
    printf "bootstrap.sh: Intermediate certificate secret exists and matches, skipping creation\n" >&2
  fi
}

setup_issuer_provisioner() {
  printf "bootstrap.sh: Setting up step issuer provisioner\n" >&2
  local jwk_is_new=false

  mkdir "$STEP_ISSUER_DIR"
  if ! kubectl get -n "$NAMESPACE" secret step-issuer-provisioner -o jsonpath='{.data.pub\.json}' | base64 -d >"$STEP_ISSUER_DIR/pub.json"; then
    printf "bootstrap.sh: step-issuer provisioner JWK does not exist, creating now\n" >&2
    rm -f "$STEP_ISSUER_DIR/pub.json"
    step crypto jwk create \
      --password-file="$STEPPATH/step-issuer-provisioner-password/password" \
      --use sig \
      "$STEP_ISSUER_DIR/pub.json" "$STEP_ISSUER_DIR/priv.json"
    kubectl create -n "$NAMESPACE" secret generic step-issuer-provisioner \
      --from-file="$STEP_ISSUER_DIR/pub.json" \
      --from-file="$STEP_ISSUER_DIR/priv.json"
  else
    printf "bootstrap.sh: step-issuer provisioner JWK exists, skipping creation\n" >&2
  fi

  kubectl get stepclusterissuer step-issuer -ojsonpath='{.spec.caBundle}' | base64 -d >"$STEP_ISSUER_DIR/caBundle.key" || true
  if $jwk_is_new || ! diff -q "$ROOT_CRT_PATH" "$STEP_ISSUER_DIR/caBundle.key"; then
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
      key: password" "$(base64 -w0 "$ROOT_CRT_PATH")" "$(step crypto jwk thumbprint < "$STEP_ISSUER_DIR/pub.json")"
    )
  else
    printf "bootstrap.sh: StepClusterIssuer exists, skipping creation\n" >&2
  fi
}

create_ssh_host_provisioner_key() {
  printf "bootstrap.sh: Setting up SSH provisioner\n" >&2
  local jwk_is_new=false

  mkdir "$SSH_HOST_DIR"
  if ! kubectl get -n "$NAMESPACE" secret ssh-host-provisioner -o jsonpath='{.data.pub\.json}' | base64 -d >"$SSH_HOST_DIR/pub.json"; then
    printf "bootstrap.sh: ssh-host-provisioner provisioner JWK does not exist, creating now\n" >&2
    rm -f "$SSH_HOST_DIR/pub.json"
    step crypto jwk create \
      --password-file="$STEPPATH/ssh-host-provisioner-password/password" \
      --use sig \
      "$SSH_HOST_DIR/pub.json" "$SSH_HOST_DIR/priv.json"
    kubectl create -n "$NAMESPACE" secret generic ssh-host-provisioner \
      --from-file="$SSH_HOST_DIR/pub.json" \
      --from-file="$SSH_HOST_DIR/priv.json"
  else
    printf "bootstrap.sh: ssh-host provisioner JWK exists, skipping creation\n" >&2
  fi
}

main "$@"
