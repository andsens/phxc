#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit
# shellcheck disable=SC1091
source /usr/local/lib/upkg/.upkg/records.sh/records.sh

KUBE_CLIENT_CA_KEY_PATH=$STEPPATH/certs/kube_apiserver_client_ca_key
KUBE_CLIENT_CA_CRT_PATH=$STEPPATH/certs/kube_apiserver_client_ca.crt

main() {
  local config lb_pv4 lb_ipv6
  lb_pv4=$(kubectl -n smallstep get svc kube-apiserver-client-ca-external -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
  lb_ipv6=$(kubectl -n smallstep get svc kube-apiserver-client-ca-external -o=jsonpath='{.status.loadBalancer.ingress[1].ip}')
  config=$(jq \
    --arg nodename "$NODENAME" \
    --arg ipv4 "$lb_pv4" \
    --arg ipv6 "$lb_ipv6" \
    --arg domain "pki-kube.$CLUSTER_DOMAIN" \
    '.dnsNames+=[$nodename, $ipv4, $ipv6, $domain]' \
    "$STEPPATH/config-ro/kube-apiserver-client-ca.json")

  local name provisioner_names=(kube-apiserver-client-ca admin)

  info "Storing and then removing %s provisioners" "${provisioner_names[*]}"

  declare -A configured_provisioners
  for name in "${provisioner_names[@]}"; do
    # 1. Store the configured provisioner
    configured_provisioners[$name]=$(jq --arg name "$name" '.authority.provisioners[] | select(.name==$name)' <<<"$config")
    # 2. Remove the provisioner
    config=$(jq --arg name "$name" 'del(.authority.provisioners[] | select(.name==$name))'  <<<"$config")
  done

  # 3. Add the provisioner keys through `step ca provisioner add`

  printf "%s\n" "$config" >"$STEPPATH/config/ca.json" # step operates on config/ca.json

  info "Adding kube-apiserver client CA provisioner certificate"
  step ca provisioner add kube-apiserver-client-ca --type X5C \
    --x5c-root "$KUBE_CLIENT_CA_CRT_PATH"

  info "Adding admin provisioner key"
  step ca provisioner add admin --type JWK --public-key=<(step crypto key format --jwk <<<"${CLUSTER_ADMIN_SSH_KEY:?}")

  config=$(cat "$STEPPATH/config/ca.json") # done messing with the physical ca.json, read it into $config

  # 4. Extract the added keys
  info "Merging new provisioner keys with stored provisioner config"

  declare -A provisioner_keys
  for name in "${provisioner_names[@]}"; do
    provisioner_keys[$name]=$(jq --arg name "$name" '.authority.provisioners[] | select(.name==$name)' <<<"$config")
  done

  # 5. Apply the extracted keys to the stored configs
  configured_provisioners[kube-apiserver-client-ca]=$(jq --argjson provisioner "${provisioner_keys[kube-apiserver-client-ca]}" \
    '.roots=$provisioner.roots' <<<"${configured_provisioners[kube-apiserver-client-ca]}")
  configured_provisioners[admin]=$(jq --argjson provisioner "${provisioner_keys[admin]}" \
    '.key=$provisioner.key' <<<"${configured_provisioners[admin]}")

  info "Replacing added provisioners with merged config"

  for name in "${provisioner_names[@]}"; do
    # 6. Remove the added provisioner
    config=$(jq --arg name "$name" 'del(.authority.provisioners[] | select(.name==$name))' <<<"$config")
    # 7. Insert the updated provisioner
    config=$(jq --argjson provisioner "${configured_provisioners[$name]}" '.authority.provisioners += [$provisioner]' <<<"$config")
  done

  printf "%s\n" "$config" >"$STEPPATH/config/ca.json" # done, write the config

  local certs_ram_path=$STEPPATH/certs-ram
  info "Copying kube-apiserver-client-ca cert & key to RAM backed volume"
  cp "$KUBE_CLIENT_CA_CRT_PATH" "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_CRT_PATH")"
  cp "$KUBE_CLIENT_CA_KEY_PATH" "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_KEY_PATH")"
  chown step:step "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_CRT_PATH")"
  chown step:step "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_KEY_PATH")"
}

main "$@"
