#!/bin/bash
set -Eeo pipefail; shopt -s inherit_errexit

main() {
  : "${STEPPATH:?}" "${STEP_CA_DOMAIN:?}"
  apk add --update --no-cache jq moreutils
  jq --arg domain "$STEP_CA_DOMAIN" '.dnsNames+=[$domain]' "$STEPPATH/config-ro/ca.json" > "$STEPPATH/config/ca.json"

  local kube_client_config kube_client
  info "Storing and then removing kube-apiserver-client-ca provisioner from ca.json"

  # 1. Store the provisioner configs from ca.json
  kube_client_config=$(jq '.authority.provisioners[] | select(.name=="kube-apiserver-client-ca")' "$STEPPATH/config/ca.json")

  # 2. Remove the provisioner configs from ca.json
  jq 'del(.authority.provisioners[] | select(.name=="kube-apiserver-client-ca"))' \
    "$STEPPATH/config/ca.json" | sponge "$STEPPATH/config/ca.json"

  # 3. Add the provisioner keys through `step ca provisioner add` to ca.json

  info "Adding kube-apiserver client CA provisioner certificate in ca.json"
  step ca provisioner add kube-apiserver-client-ca --type X5C \
    --x5c-root "$STEPPATH/certs/kube_apiserver_client_ca.crt"

  # 4. Read the added keys from ca.json and apply them to the stored configs
  info "Merging new provisioner keys with stored provisioner config from ca.json"

  kube_client=$(jq --argjson provisioner "$(jq '.authority.provisioners[] | select(.name=="kube-apiserver-client-ca")' "$STEPPATH/config/ca.json")" \
    '.roots=$provisioner.roots' <<<"$kube_client_config")

  # 5. Replace the added provisioners in ca.json with the updated provisioner
  info "Replacing added provisioners with merged config"

  jq 'del(.authority.provisioners[] | select(.name=="kube-apiserver-client-ca"))' \
    "$STEPPATH/config/ca.json" | sponge "$STEPPATH/config/ca.json"
  jq --argjson kube_client "$kube_client" \
    '.authority.provisioners += [$kube_client]' \
    "$STEPPATH/config/ca.json" | sponge "$STEPPATH/config/ca.json"
}

info() {
  local tpl=$1; shift
  # shellcheck disable=2059
  printf "setup-kube-apiserver-client-ca-config.sh: $tpl\n" "$@" >&2
}

main "$@"
