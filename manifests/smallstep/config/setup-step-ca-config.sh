#!/bin/bash
set -Eeo pipefail

main() {
  : "${STEPPATH:?}" "${STEP_CA_DOMAIN:?}"
  apk add --update --no-cache jq moreutils
  jq --arg domain "$STEP_CA_DOMAIN" '.dnsNames+=[$domain]' "$STEPPATH/config-ro/ca.json" > "$STEPPATH/config/ca.json"

  local step_issuer_config ssh_host_config kube_client_config step_issuer ssh_host kube_client
  info "Storing and then removing step-issuer, ssh-host, and kube-apiserver-client-ca provisioners from ca.json"

  # 1. Store the provisioner configs from ca.json
  step_issuer_config=$(jq '.authority.provisioners[] | select(.name=="step-issuer")' "$STEPPATH/config/ca.json")
  ssh_host_config=$(jq '.authority.provisioners[] | select(.name=="ssh-host")' "$STEPPATH/config/ca.json")
  kube_client_config=$(jq '.authority.provisioners[] | select(.name=="kube-apiserver-client-ca")' "$STEPPATH/config/ca.json")

  # 2. Remove the provisioner configs from ca.json
  jq 'del(.authority.provisioners[] | select(.name=="step-issuer" or .name=="ssh-host" or .name=="kube-apiserver-client-ca"))' \
    "$STEPPATH/config/ca.json" | sponge "$STEPPATH/config/ca.json"

  # 3. Add the provisioner keys through `step ca provisioner add` to ca.json

  info "Adding step-issuer provisioner key in ca.json"
  step ca provisioner add step-issuer --type JWK \
    --public-key="$STEPPATH/certs/step-issuer-provisioner/pub.json" \
    --private-key="$STEPPATH/certs/step-issuer-provisioner/priv.json" \
    --password-file="$STEPPATH/step-issuer-provisioner-password/password"

  info "Adding ssh-host provisioner key in ca.json"
  step ca provisioner add ssh-host --type JWK \
    --public-key="$STEPPATH/certs/ssh-host-provisioner/pub.json" \
    --private-key="$STEPPATH/certs/ssh-host-provisioner/priv.json" \
    --password-file="$STEPPATH/ssh-host-provisioner-password/password"

  info "Adding kube-apiserver client CA provisioner certificate in ca.json"
  step ca provisioner add kube-apiserver-client-ca --type X5C \
    --x5c-root "$STEPPATH/certs/kube_apiserver_client_ca.crt"

  # 4. Read the added keys from ca.json and apply them to the stored configs
  info "Merging new provisioner keys with stored provisioner config from ca.json"

  step_issuer=$(jq --argjson provisioner "$(jq '.authority.provisioners[] | select(.name=="step-issuer")' "$STEPPATH/config/ca.json")" \
    '.key=$provisioner.key | .encryptedKey=$provisioner.encryptedKey' <<<"$step_issuer_config")
  ssh_host=$(jq --argjson provisioner "$(jq '.authority.provisioners[] | select(.name=="ssh-host")' "$STEPPATH/config/ca.json")" \
    '.key=$provisioner.key | .encryptedKey=$provisioner.encryptedKey' <<<"$ssh_host_config")
  kube_client=$(jq --argjson provisioner "$(jq '.authority.provisioners[] | select(.name=="kube-apiserver-client-ca")' "$STEPPATH/config/ca.json")" \
    '.roots=$provisioner.roots' <<<"$kube_client_config")

  # 5. Replace the added provisioners in ca.json with the updated provisioner
  info "Replacing added provisioners with merged config"

  jq 'del(.authority.provisioners[] | select(.name=="step-issuer" or .name=="ssh-host" or .name=="kube-apiserver-client-ca"))' \
    "$STEPPATH/config/ca.json" | sponge "$STEPPATH/config/ca.json"
  jq --argjson step_issuer "$step_issuer" --argjson ssh_host "$ssh_host" --argjson kube_client "$kube_client" \
    '.authority.provisioners += [$step_issuer, $ssh_host, $kube_client]' \
    "$STEPPATH/config/ca.json" | sponge "$STEPPATH/config/ca.json"
}

info() {
  local tpl=$1; shift
  # shellcheck disable=2059
  printf "%s: $tpl\n" "$(basename "$0")" "$@" >&2
}

main "$@"
