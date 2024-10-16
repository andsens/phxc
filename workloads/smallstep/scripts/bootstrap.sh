#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit
# shellcheck disable=SC1091
source /usr/local/lib/upkg/.upkg/records.sh/records.sh

ROOT_KEY_PATH=$STEPPATH/certs/root_ca/tls.key
ROOT_CRT_PATH=$STEPPATH/certs/root_ca/tls.crt

INTERMEDIATE_KEY_PATH=$STEPPATH/certs/intermediate_ca_key
INTERMEDIATE_CRT_PATH=$STEPPATH/certs/intermediate_ca.crt

main() {
  create_intermediate_ca
  create_step_issuer_provisioner
  create_ssh_host_provisioner
  create_kube_apiserver_client_ca_secret
}

create_intermediate_ca() {
  info "Creating smallstep intermediate certificate secret"
  if (kubectl get -n smallstep secret smallstep-intermediate -o jsonpath='{.data.tls\.crt}' | base64 -d) >"$INTERMEDIATE_CRT_PATH" 2>/dev/null; then
    if step certificate verify "$INTERMEDIATE_CRT_PATH" --roots="$ROOT_CRT_PATH" && \
       step certificate needs-renewal "$INTERMEDIATE_CRT_PATH"; then
      info "Intermediate CA secret validation succeeded"
    else
      info "Intermediate CA validation failed"
      rm "$INTERMEDIATE_CRT_PATH"
    fi
  else
    info "Intermediate CA not found"
    rm "$INTERMEDIATE_CRT_PATH"
  fi
  if [[ ! -e "$INTERMEDIATE_CRT_PATH" ]]; then
    info "Creating intermediate CA"
    step certificate create --profile=intermediate-ca \
      --force --no-password --insecure \
      --not-after=87600h \
      --ca="$ROOT_CRT_PATH" --ca-key="$ROOT_KEY_PATH" \
      "${CLUSTER_PKINAME:?}" "$INTERMEDIATE_CRT_PATH" "$INTERMEDIATE_KEY_PATH"
    kubectl delete -n smallstep secret smallstep-intermediate 2>/dev/null || true
    kubectl create -n smallstep secret tls smallstep-intermediate --cert="$INTERMEDIATE_CRT_PATH" --key="$INTERMEDIATE_KEY_PATH"
  fi
}

create_step_issuer_provisioner() {
  info "Setting up step issuer provisioner"
  local step_issuer_dir=$STEPPATH/certs/step-issuer-provisioner

  mkdir "$step_issuer_dir"
  if ! kubectl get -n smallstep secret step-issuer-provisioner -o jsonpath='{.data.pub\.json}' | base64 -d >"$step_issuer_dir/pub.json"; then
    info "step-issuer provisioner validation failed, (re-)creating now"
    step crypto jwk create \
      --force --password-file="$STEPPATH/step-issuer-provisioner-password/password" \
      --use sig \
      "$step_issuer_dir/pub.json" "$step_issuer_dir/priv.json"
    kubectl create -n smallstep secret generic step-issuer-provisioner \
      --from-file="$step_issuer_dir/pub.json" \
      --from-file="$step_issuer_dir/priv.json"
  else
    info "step-issuer provisioner validation succeeded"
  fi

  kubectl get -n smallstep stepclusterissuer step-issuer -ojsonpath='{.spec.caBundle}' | base64 -d >"$step_issuer_dir/caBundle.key" || true
  local expected_kid actual_kid
  expected_kid=$(step crypto jwk thumbprint < "$step_issuer_dir/pub.json")
  actual_kid=$(kubectl get -n smallstep stepclusterissuer step-issuer -ojsonpath='{.spec.provisioner.kid}' || true)
  if ! diff -q "$ROOT_CRT_PATH" "$step_issuer_dir/caBundle.key" || [[ $actual_kid != "$expected_kid" ]]; then
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
      key: password" smallstep "$(base64 -w0 "$ROOT_CRT_PATH")" "$(step crypto jwk thumbprint < "$step_issuer_dir/pub.json")"
    )
  else
    info "StepClusterIssuer validation succeeded"
  fi
}

create_ssh_host_provisioner() {
  info "Setting up SSH host provisioner"
  local ssh_host_dir=$STEPPATH/certs/ssh-host-provisioner

  mkdir "$ssh_host_dir"
  if ! kubectl get -n smallstep secret ssh-host-provisioner -o jsonpath='{.data.pub\.json}' | base64 -d >"$ssh_host_dir/pub.json"; then
    info "ssh-host provisioner validation failed, (re-)creating now"
    step crypto jwk create \
      --force --password-file="$STEPPATH/ssh-host-provisioner-password/password" \
      --use sig \
      "$ssh_host_dir/pub.json" "$ssh_host_dir/priv.json"
    kubectl create -n smallstep secret generic ssh-host-provisioner \
      --from-file="$ssh_host_dir/pub.json" \
      --from-file="$ssh_host_dir/priv.json"
  else
    info "ssh-host provisioner validation succeeded"
  fi
}

create_kube_apiserver_client_ca_secret() {
  info "Setting up kube-apiserver client CA certificate secret"
  local cert_path=/home/step/certs/kube_apiserver_client_ca.crt
  cert=$(cat $cert_path)
  if [[ $(kubectl get -n "$NAMESPACE" secret kube-apiserver-client-ca -o jsonpath='{.data.tls\.crt}' | base64 -d) != "$cert" ]]; then
    info "kube-apiserver client CA certificate secret validation failed, (re-)creating now"
    kubectl delete -n "$NAMESPACE" secret kube-apiserver-client-ca 2>/dev/null || true
    kubectl create -n "$NAMESPACE" secret generic kube-apiserver-client-ca --from-file=tls.crt=$cert_path
  else
    info "kube-apiserver client CA certificate secret validation succeeded"
  fi
}

main "$@"
