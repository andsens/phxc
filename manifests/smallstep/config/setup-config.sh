#!/bin/bash
set -Eeo pipefail

main() {
  : "${STEPPATH:?}" "${STEP_CA_DOMAIN:?}"
  apk add --update --no-cache jq moreutils
  jq --arg domain "$STEP_CA_DOMAIN" '.dnsNames+=[$domain]' "$STEPPATH/config-ro/ca.json" > "$STEPPATH/config/ca.json"

  local step_issuer_config ssh_host_config step_issuer ssh_host
  info "Storing and then removing step-issuer & ssh-host provisioners from ca.json"
  # 1. Store the provisioner configs from ca.json
  step_issuer_config=$(jq '.authority.provisioners[] | select(.name=="step-issuer")' "$STEPPATH/config/ca.json")
  ssh_host_config=$(jq '.authority.provisioners[] | select(.name=="ssh-host")' "$STEPPATH/config/ca.json")
  # 2. Remove the provisioner configs from ca.json
  jq 'del(.authority.provisioners[] | select(.name=="step-issuer" or .name=="ssh-host"))' "$STEPPATH/config/ca.json" | sponge "$STEPPATH/config/ca.json"
  info "Adding step-issuer provisioner key in ca.json"
  # 3. Add the provisioner keys through `step ca provisioner add` to ca.json
  step ca provisioner add step-issuer \
    --public-key="$STEPPATH/certs/step-issuer-provisioner/pub.json" \
    --private-key="$STEPPATH/certs/step-issuer-provisioner/priv.json" \
    --password-file="$STEPPATH/step-issuer-provisioner-password/password"
  info "Adding ssh-host provisioner key in ca.json"
  step ca provisioner add ssh-host \
    --public-key="$STEPPATH/certs/ssh-host-provisioner/pub.json" \
    --private-key="$STEPPATH/certs/ssh-host-provisioner/priv.json" \
    --password-file="$STEPPATH/ssh-host-provisioner-password/password"
  info "Merging new provisioner keys with stored provisioner config from ca.json"
  # 4. Read the added keys from ca.json and apply them to the stored configs
  step_issuer=$(jq --argjson key "$(jq '.authority.provisioners[] | select(.name=="step-issuer")' "$STEPPATH/config/ca.json")" \
    '.key=$key.key | .encryptedKey=$key.encryptedKey' <<<"$step_issuer_config")
  ssh_host=$(jq --argjson key "$(jq '.authority.provisioners[] | select(.name=="ssh-host")' "$STEPPATH/config/ca.json")" \
    '.key=$key.key | .encryptedKey=$key.encryptedKey' <<<"$ssh_host_config")
  info "Replacing added provisioners with merged config"
  # 5. Remove the added provisioners configs from ca.json
  jq 'del(.authority.provisioners[] | select(.name=="step-issuer" or .name=="ssh-host"))' "$STEPPATH/config/ca.json" | sponge "$STEPPATH/config/ca.json"
  # 6. Add the updated provisioner configs to ca.json
  jq --argjson step_issuer "$step_issuer" --argjson ssh_host "$ssh_host" \
    '.authority.provisioners += [$step_issuer, $ssh_host]' "$STEPPATH/config/ca.json" | sponge "$STEPPATH/config/ca.json"
}

info() {
  local tpl=$1; shift
  # shellcheck disable=2059
  printf "setup-config.sh: $tpl\n" "$@" >&2
}

main "$@"
