#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=/usr/local/lib/upkg
source "$PKGROOT/.upkg/records.sh/records.sh"

export STEPPATH=/home/step
KUBE_SERVER_CA_KEY_PATH=$STEPPATH/kube-api-secrets/kube_apiserver_server_ca_key
KUBE_SERVER_CA_CRT_PATH=$STEPPATH/kube-api-secrets/kube_apiserver_server_ca.crt
KUBE_SERVER_ISSUER_DIR=$STEPPATH/setup-secrets/kube-server-issuer
SSH_HOST_DIR=$STEPPATH/setup-secrets/ssh-host

main() {
  create_kube_server_issuer_provisioner
  create_ssh_host_provisioner
  local kube_server_issuer_jwk kube_server_issuer_enc_key ssh_host_jwk ssh_host_enc_key
  kube_server_issuer_jwk=$(cat "$KUBE_SERVER_ISSUER_DIR/pub.json")
  kube_server_issuer_enc_key=$(jq -rcS '. | join(".")' "$KUBE_SERVER_ISSUER_DIR/priv.json")
  ssh_host_jwk=$(cat "$SSH_HOST_DIR/pub.json")
  ssh_host_enc_key=$(jq -rcS '. | join(".")' "$SSH_HOST_DIR/priv.json")
  info "Creating CA config"
  jq \
    --argjson kube_server_issuer_jwk "$kube_server_issuer_jwk" \
    --arg kube_server_issuer_enc_key "$kube_server_issuer_enc_key" \
    --argjson ssh_host_jwk "$ssh_host_jwk" \
    --arg ssh_host_enc_key "$ssh_host_enc_key" '
    (.authority.provisioners[] | select(.name=="kube-server-issuer") | .key) |= $kube_server_issuer_jwk |
    (.authority.provisioners[] | select(.name=="kube-server-issuer") | .encryptedKey) |= $kube_server_issuer_enc_key |
    (.authority.provisioners[] | select(.name=="ssh-host") | .key) |= $ssh_host_jwk |
    (.authority.provisioners[] | select(.name=="ssh-host") | .encryptedKey) |= $ssh_host_enc_key
    ' "$STEPPATH/config-ro/kube-server-ca.json" >"$STEPPATH/config/ca.json"

  local certs_ram_path=$STEPPATH/secrets
  info "Copying kube-server-ca cert & key to RAM backed volume"
  cp "$KUBE_SERVER_CA_CRT_PATH" "$certs_ram_path/$(basename "$KUBE_SERVER_CA_CRT_PATH")"
  cp "$KUBE_SERVER_CA_KEY_PATH" "$certs_ram_path/$(basename "$KUBE_SERVER_CA_KEY_PATH")"
  chown 1000:1000 "$certs_ram_path/$(basename "$KUBE_SERVER_CA_CRT_PATH")"
  chown 1000:1000 "$certs_ram_path/$(basename "$KUBE_SERVER_CA_KEY_PATH")"
}

create_kube_server_issuer_provisioner() {
  info "Setting up kube-server-issuer provisioner"

  mkdir -p "$KUBE_SERVER_ISSUER_DIR"
  if ! kubectl get -n smallstep secret kube-server-issuer-provisioner-password -o jsonpath='{.data.password}' >"$KUBE_SERVER_ISSUER_DIR/password"; then
    (tr -dc A-Za-z0-9_- </dev/urandom | head -c 32 || true) >"$KUBE_SERVER_ISSUER_DIR/password"
    info "kube-server-issuer provisioner password does not exist, creating now"
    kubectl create -n smallstep secret generic kube-server-issuer-provisioner-password --from-file="$KUBE_SERVER_ISSUER_DIR/password"
  else
    info "kube-server-issuer provisioner password exists"
  fi
  if ! kubectl get -n smallstep secret kube-server-issuer-provisioner -o jsonpath='{.data.pub\.json}' | base64 -d >"$KUBE_SERVER_ISSUER_DIR/pub.json"; then
    info "kube-server-issuer provisioner validation failed, (re-)creating now"
    step crypto jwk create \
      --force --password-file="$KUBE_SERVER_ISSUER_DIR/password" --use sig \
      "$KUBE_SERVER_ISSUER_DIR/pub.json" "$KUBE_SERVER_ISSUER_DIR/priv.json"
    kubectl create -n smallstep secret generic kube-server-issuer-provisioner \
      --from-file="$KUBE_SERVER_ISSUER_DIR/pub.json" \
      --from-file="$KUBE_SERVER_ISSUER_DIR/priv.json"
  else
    kubectl get -n smallstep secret kube-server-issuer-provisioner -o jsonpath='{.data.priv\.json}' | base64 -d >"$KUBE_SERVER_ISSUER_DIR/priv.json"
    info "kube-server-issuer provisioner validation succeeded"
  fi

  kubectl get -n smallstep stepclusterissuer kube-server-issuer -ojsonpath='{.spec.caBundle}' | base64 -d >"$KUBE_SERVER_ISSUER_DIR/caBundle.key" || true
  local expected_kid actual_kid
  expected_kid=$(step crypto jwk thumbprint < "$KUBE_SERVER_ISSUER_DIR/pub.json")
  actual_kid=$(kubectl get -n smallstep stepclusterissuer kube-server-issuer -ojsonpath='{.spec.provisioner.kid}' || true)
  if ! diff -q "$KUBE_SERVER_CA_CRT_PATH" "$KUBE_SERVER_ISSUER_DIR/caBundle.key" || [[ $actual_kid != "$expected_kid" ]]; then
    info "StepClusterIssuer validation failed, (re-)creating now"
    local root_b64 kube_server_issuer_fp
    root_b64=$(base64 -w0 "$KUBE_SERVER_CA_CRT_PATH")
    kube_server_issuer_fp=$(step crypto jwk thumbprint < "$KUBE_SERVER_ISSUER_DIR/pub.json")
    kubectl apply -f <(printf -- "apiVersion: certmanager.step.sm/v1beta1
kind: StepClusterIssuer
metadata:
  name: kube-server
  namespace: %s
spec:
  url: https://kube-server-ca.smallstep.svc.cluster.local:9000
  caBundle: %s
  provisioner:
    name: kube-server-issuer
    kid: %s
    passwordRef:
      namespace: smallstep
      name: kube-server-issuer-provisioner-password
      key: password" smallstep "$root_b64" "$kube_server_issuer_fp"
    )
  else
    info "StepClusterIssuer validation succeeded"
  fi
}

create_ssh_host_provisioner() {
  info "Setting up SSH host provisioner"

  mkdir -p "$SSH_HOST_DIR"
  if ! kubectl get -n smallstep secret ssh-host-provisioner-password -o jsonpath='{.data.password}' >"$SSH_HOST_DIR/password"; then
    info "step-host provisioner password does not exist, creating now"
    (tr -dc A-Za-z0-9_- </dev/urandom | head -c 32 || true) >"$SSH_HOST_DIR/password"
    kubectl create -n smallstep secret generic ssh-host-provisioner-password --from-file="$SSH_HOST_DIR/password"
  else
    info "step-host provisioner password exists"
  fi
  if ! kubectl get -n smallstep secret ssh-host-provisioner -o jsonpath='{.data.pub\.json}' | base64 -d >"$SSH_HOST_DIR/pub.json"; then
    info "ssh-host provisioner validation failed, (re-)creating now"
    step crypto jwk create \
      --force --password-file="$SSH_HOST_DIR/password" \
      --use sig \
      "$SSH_HOST_DIR/pub.json" "$SSH_HOST_DIR/priv.json"
    kubectl create -n smallstep secret generic ssh-host-provisioner \
      --from-file="$SSH_HOST_DIR/pub.json" \
      --from-file="$SSH_HOST_DIR/priv.json"
  else
    kubectl get -n smallstep secret ssh-host-provisioner -o jsonpath='{.data.priv\.json}' | base64 -d >"$SSH_HOST_DIR/priv.json"
    info "ssh-host provisioner validation succeeded"
  fi
}

main "$@"
