#!/bin/bash
set -Eeo pipefail; shopt -s inherit_errexit

: "${PKI_NAME:?}" "${STEPPATH:?}" "${NAMESPACE:?}" "${K8S_API_HOST:?}" "${KUBE_CONFIG_OWNER:?}"
ROOT_CRT_PATH=$STEPPATH/persistent-certs/root_ca.crt
STEP_ISSUER_DIR=$STEPPATH/certs/step-issuer-provisioner

main() {
  info "Setting up step issuer provisioner"

  mkdir "$STEP_ISSUER_DIR"
  if ! kubectl get -n "$NAMESPACE" secret step-issuer-provisioner -o jsonpath='{.data.pub\.json}' | base64 -d >"$STEP_ISSUER_DIR/pub.json"; then
    info "step-issuer provisioner validation failed, (re-)creating now"
    step crypto jwk create \
      --force --password-file="$STEPPATH/step-issuer-provisioner-password/password" \
      --use sig \
      "$STEP_ISSUER_DIR/pub.json" "$STEP_ISSUER_DIR/priv.json"
    kubectl create -n "$NAMESPACE" secret generic step-issuer-provisioner \
      --from-file="$STEP_ISSUER_DIR/pub.json" \
      --from-file="$STEP_ISSUER_DIR/priv.json"
  else
    info "step-issuer provisioner validation succeeded"
  fi

  kubectl get -n "$NAMESPACE" stepclusterissuer step-issuer -ojsonpath='{.spec.caBundle}' | base64 -d >"$STEP_ISSUER_DIR/caBundle.key" || true
  local expected_kid actual_kid
  expected_kid=$(step crypto jwk thumbprint < "$STEP_ISSUER_DIR/pub.json")
  actual_kid=$(kubectl get -n "$NAMESPACE" stepclusterissuer step-issuer -ojsonpath='{.spec.provisioner.kid}' || true)
  if ! diff -q "$ROOT_CRT_PATH" "$STEP_ISSUER_DIR/caBundle.key" || [[ $actual_kid != "$expected_kid" ]]; then
    info "StepClusterIssuer validation failed, (re-)creating now"
    kubectl apply -f <(printf -- "apiVersion: certmanager.step.sm/v1beta1
kind: StepClusterIssuer
metadata:
  name: step-issuer
  namespace: %s
spec:
  url: https://step-ca.smallstep.svc.cluster.local:9000
  caBundle: %s
  provisioner:
    name: step-issuer
    kid: %s
    passwordRef:
      namespace: smallstep
      name: step-issuer-provisioner-password
      key: password" "$NAMESPACE" "$(base64 -w0 "$ROOT_CRT_PATH")" "$(step crypto jwk thumbprint < "$STEP_ISSUER_DIR/pub.json")"
    )
  else
    info "StepClusterIssuer validation succeeded"
  fi
}

info() {
  local tpl=$1; shift
  # shellcheck disable=2059
  printf "%s: $tpl\n" "$(basename "$0")" "$@" >&2
}

main "$@"
