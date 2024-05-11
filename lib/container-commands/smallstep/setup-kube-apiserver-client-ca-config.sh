#!/bin/bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")
source "$PKGROOT/lib/common.sh"
source "$PKGROOT/lib/container-commands/smallstep/paths.sh"


main() {
  setup_config
  copy_ca
}

setup_config() {
  local config
  config=$(jq --arg domain "pki-kube.$(get_setting cluster.domain)" '.dnsNames+=[$domain]' "/var/lib/home-cluster/config/smallstep/kube-apiserver-client-ca.json")

  local kube_client_config kube_client
  info "Storing and then removing kube-apiserver-client-ca provisioner"

  # 1. Store the provisioner config
  kube_client_config=$(jq '.authority.provisioners[] | select(.name=="kube-apiserver-client-ca")' <<<"$config")

  # 2. Remove the provisioner config
  config=$(jq 'del(.authority.provisioners[] | select(.name=="kube-apiserver-client-ca"))' <<<"$config")

  # 3. Add the provisioner key through `step ca provisioner add`

  printf "%s\n" "$config" >"$STEPPATH/config/ca.json" # step operates on config/ca.json

  info "Adding kube-apiserver client CA provisioner certificate"
  step ca provisioner add kube-apiserver-client-ca --type X5C \
    --x5c-root "$KUBE_CLIENT_CA_CRT_PATH"

  config=$(cat "$STEPPATH/config/ca.json") # done messing with the physical ca.json, read it into $config

  # 4. Extract the added key
  info "Merging new provisioner keys with stored provisioner config"

  local provisioner_key
  provisioner_key=$(jq '.authority.provisioners[] | select(.name=="kube-apiserver-client-ca")' <<<"$config")

  # 5. Apply the extracted keys to the stored configs
  kube_client=$(jq --argjson provisioner "$provisioner_key" '.roots=$provisioner.roots' <<<"$kube_client_config")

  info "Replacing added provisioners with merged config"
  # 6. Remove the added provisioner
  config=$(jq 'del(.authority.provisioners[] | select(.name=="kube-apiserver-client-ca"))' <<<"$config")

  # 7. Insert the updated provisioner
  config=$(jq --argjson kube_client "$kube_client" '.authority.provisioners += [$kube_client]' <<<"$config")

  printf "%s\n" "$config" >"$STEPPATH/config/ca.json" # done, write the config
}

copy_ca() {
  local certs_ram_path=$STEPPATH/certs-ram
  info "Copying kube-apiserver-client-ca cert & key to RAM backed volume"
  cp "$KUBE_CLIENT_CA_CRT_PATH" "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_CRT_PATH")"
  cp "$KUBE_CLIENT_CA_KEY_PATH" "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_KEY_PATH")"
  chown step:step "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_CRT_PATH")"
  chown step:step "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_KEY_PATH")"
}

main "$@"
