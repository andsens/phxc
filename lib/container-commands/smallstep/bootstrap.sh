#!/bin/bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")
apk add jq py3-pip
pip install -q yq
source "$PKGROOT/lib/common.sh"
source "$PKGROOT/lib/container-commands/smallstep/paths.sh"

main() {
  create_ca_certificates
  create_ca_secrets
  create_step_issuer_provisioner
  create_ssh_host_provisioner
  "$PKGROOT/lib/container-commands/create-kube-apiserver-client-ca-secret.sh" /home/step/certs/kube_apiserver_client_ca.crt
  "$PKGROOT/lib/container-commands/smallstep/create-kube-config.sh" system:admin system:masters
}

create_ca_certificates() {
  info "Setting up root and intermediate certificates"
  local pki_name
  pki_name=$(get_setting cluster.pkiName)
  if [[ ! -e $ROOT_KEY_PATH ]] || \
          step certificate needs-renewal "$ROOT_CRT_PATH"; then
    info "Root CA validation failed, (re-)creating now"
    step certificate create --profile=root-ca \
      --force --no-password --insecure \
      --not-after=87600h \
      "$pki_name Root" "$ROOT_CRT_PATH" "$ROOT_KEY_PATH"
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
      "$pki_name" "$INTERMEDIATE_CRT_PATH" "$INTERMEDIATE_KEY_PATH"
  else
    info "Intermediate CA validation succeeded"
  fi
}

create_ca_secrets() {
  info "Creating smallstep certificate chain secrets"

  if [[ $(kubectl get -n smallstep secret smallstep-root -o jsonpath='{.data.tls\.crt}' | base64 -d) != $(cat "$ROOT_CRT_PATH") ]]; then
    info "Root CA secret validation failed, (re-)creating now"
    kubectl delete -n smallstep secret smallstep-root 2>/dev/null || true
    kubectl create -n smallstep secret generic smallstep-root --from-file=tls.crt="$ROOT_CRT_PATH"
  else
    info "Root CA secret validation succeeded"
  fi

  if [[ $(kubectl get -n smallstep secret smallstep-intermediate -o jsonpath='{.data.tls\.crt}' | base64 -d) != $(cat "$INTERMEDIATE_CRT_PATH") ]]; then
    info "Intermediate CA secret validation failed, (re-)creating now"
    kubectl delete -n smallstep secret smallstep-intermediate 2>/dev/null || true
    kubectl create -n smallstep secret tls smallstep-intermediate --cert="$INTERMEDIATE_CRT_PATH" --key="$INTERMEDIATE_KEY_PATH"
  else
    info "Intermediate CA secret validation succeeded"
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

main "$@"
