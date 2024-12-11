#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit
# shellcheck disable=SC1091
source /usr/local/lib/upkg/.upkg/records.sh/records.sh

ROOT_CRT_PATH=/home/step/certs/root_ca.crt
STEP_ISSUER_DIR=$STEPPATH/provisioner-secrets/step-issuer
SSH_HOST_DIR=$STEPPATH/provisioner-secrets/ssh-host

main() {
  create_step_issuer_provisioner
  create_ssh_host_provisioner
  local lb_ipv4 lb_ipv6 step_issuer_jwk step_issuer_enc_key ssh_host_jwk ssh_host_enc_key
  lb_ipv4=$(kubectl -n smallstep get svc step-ca-external -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
  lb_ipv6=$(kubectl -n smallstep get svc step-ca-external -o=jsonpath='{.status.loadBalancer.ingress[1].ip}')
  step_issuer_jwk=$(cat "$STEP_ISSUER_DIR/pub.json")
  step_issuer_enc_key=$(jq -cS . "$STEP_ISSUER_DIR/priv.json" | base64 -w0 | tr -d '=' | tr '/+' '_-')
  ssh_host_jwk=$(cat "$SSH_HOST_DIR/pub.json")
  ssh_host_enc_key=$(jq -cS . "$SSH_HOST_DIR/priv.json" | base64 -w0 | tr -d '=' | tr '/+' '_-')
  info "Creating CA config"
  jq \
    --arg ipv4 "$lb_ipv4" \
    --arg ipv6 "$lb_ipv6" \
    --arg domain "pki.$CLUSTER_DOMAIN" \
    --argjson step_issuer_jwk "$step_issuer_jwk" \
    --arg step_issuer_enc_key "$step_issuer_enc_key" \
    --argjson ssh_host_jwk "$ssh_host_jwk" \
    --arg ssh_host_enc_key "$ssh_host_enc_key" '
    .dnsNames+=[$ipv4, $ipv6, $domain] |
    (.authority.provisioners[] | select(.name=="step-issuer") | .key) |= $step_issuer_jwk |
    (.authority.provisioners[] | select(.name=="step-issuer") | .encryptedKey) |= $step_issuer_enc_key |
    (.authority.provisioners[] | select(.name=="ssh-host") | .key) |= $ssh_host_jwk |
    (.authority.provisioners[] | select(.name=="ssh-host") | .encryptedKey) |= $ssh_host_enc_key
    ' "$STEPPATH/config-ro/ca.json" >"$STEPPATH/config/ca.json"
}

create_step_issuer_provisioner() {
  info "Setting up step issuer provisioner"

  mkdir -p "$STEP_ISSUER_DIR"
  if ! kubectl get -n smallstep secret step-issuer-provisioner-password -o jsonpath='{.data.password}' >"$STEP_ISSUER_DIR/password"; then
    (tr -dc A-Za-z0-9_- </dev/urandom | head -c 32 || true) >"$STEP_ISSUER_DIR/password"
    info "step-issuer provisioner password does not exist, creating now"
    kubectl create -n smallstep secret generic step-issuer-provisioner-password --from-file="$STEP_ISSUER_DIR/password"
  else
    info "step-issuer provisioner password exists"
  fi
  if ! kubectl get -n smallstep secret step-issuer-provisioner -o jsonpath='{.data.pub\.json}' | base64 -d >"$STEP_ISSUER_DIR/pub.json"; then
    info "step-issuer provisioner validation failed, (re-)creating now"
    step crypto jwk create \
      --force --password-file="$STEP_ISSUER_DIR/password" --use sig \
      "$STEP_ISSUER_DIR/pub.json" "$STEP_ISSUER_DIR/priv.json"
    kubectl create -n smallstep secret generic step-issuer-provisioner \
      --from-file="$STEP_ISSUER_DIR/pub.json" \
      --from-file="$STEP_ISSUER_DIR/priv.json"
  else
    kubectl get -n smallstep secret step-issuer-provisioner -o jsonpath='{.data.priv\.json}' | base64 -d >"$STEP_ISSUER_DIR/priv.json"
    info "step-issuer provisioner validation succeeded"
  fi

  kubectl get -n smallstep stepclusterissuer step-issuer -ojsonpath='{.spec.caBundle}' | base64 -d >"$STEP_ISSUER_DIR/caBundle.key" || true
  local expected_kid actual_kid
  expected_kid=$(step crypto jwk thumbprint < "$STEP_ISSUER_DIR/pub.json")
  actual_kid=$(kubectl get -n smallstep stepclusterissuer step-issuer -ojsonpath='{.spec.provisioner.kid}' || true)
  if ! diff -q "$ROOT_CRT_PATH" "$STEP_ISSUER_DIR/caBundle.key" || [[ $actual_kid != "$expected_kid" ]]; then
    info "StepClusterIssuer validation failed, (re-)creating now"
    local root_b64 step_issuer_fp
    root_b64=$(base64 -w0 "$ROOT_CRT_PATH")
    step_issuer_fp=$(step crypto jwk thumbprint < "$STEP_ISSUER_DIR/pub.json")
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
      key: password" smallstep "$root_b64" "$step_issuer_fp"
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
