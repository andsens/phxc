#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit
# shellcheck disable=SC1091
source /usr/local/lib/upkg/.upkg/records.sh/records.sh


KUBE_CLIENT_CA_CRT_PATH=$STEPPATH/certs/kube_apiserver_client_ca.crt

main() {
  local config lb_pv4 lb_ipv6
  lb_pv4=$(kubectl -n smallstep get svc step-ca-external -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
  lb_ipv6=$(kubectl -n smallstep get svc step-ca-external -o=jsonpath='{.status.loadBalancer.ingress[1].ip}')
  config=$(jq \
    --arg ipv4 "$lb_pv4" \
    --arg ipv6 "$lb_ipv6" \
    --arg domain "pki.$CLUSTER_DOMAIN" \
    '.dnsNames+=[$ipv4, $ipv6, $domain]' \
    "$STEPPATH/config-ro/ca.json")

  local name provisioner_names=(step-issuer ssh-host kube-apiserver-client-ca)

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

  info "Adding step-issuer provisioner key"
  step ca provisioner add step-issuer --type JWK \
    --public-key="$STEPPATH/step-issuer-provisioner/pub.json" \
    --private-key="$STEPPATH/step-issuer-provisioner/priv.json" \
    --password-file="$STEPPATH/step-issuer-provisioner-password"

  info "Adding ssh-host provisioner key"
  step ca provisioner add ssh-host --type JWK \
    --public-key="$STEPPATH/ssh-host-provisioner/pub.json" \
    --private-key="$STEPPATH/ssh-host-provisioner/priv.json" \
    --password-file="$STEPPATH/ssh-host-provisioner-password"

  info "Adding kube-apiserver client CA provisioner certificate"
  step ca provisioner add kube-apiserver-client-ca --type X5C --x5c-root "$KUBE_CLIENT_CA_CRT_PATH"

  config=$(cat "$STEPPATH/config/ca.json") # done messing with the physical ca.json, read it into $config

  # 4. Extract the added keys
  info "Merging new provisioner keys with stored provisioner config"

  declare -A provisioner_keys
  for name in "${provisioner_names[@]}"; do
    provisioner_keys[$name]=$(jq --arg name "$name" '.authority.provisioners[] | select(.name==$name)' <<<"$config")
  done

  # 5. Apply the extracted keys to the stored configs
  configured_provisioners[step-issuer]=$(jq --argjson provisioner "${provisioner_keys[step-issuer]}" \
    '.key=$provisioner.key | .encryptedKey=$provisioner.encryptedKey' <<<"${configured_provisioners[step-issuer]}")
  configured_provisioners[ssh-host]=$(jq --argjson provisioner "${provisioner_keys[ssh-host]}" \
    '.key=$provisioner.key | .encryptedKey=$provisioner.encryptedKey' <<<"${configured_provisioners[ssh-host]}")
  configured_provisioners[kube-apiserver-client-ca]=$(jq --argjson provisioner "${provisioner_keys[$name]}" \
    '.roots=$provisioner.roots' <<<"${configured_provisioners[kube-apiserver-client-ca]}")

  info "Replacing added provisioners with merged config"

  for name in "${provisioner_names[@]}"; do
    # 6. Remove the added provisioner
    config=$(jq --arg name "$name" 'del(.authority.provisioners[] | select(.name==$name))' <<<"$config")
    # 7. Insert the updated provisioner
    config=$(jq --argjson provisioner "${configured_provisioners[$name]}" '.authority.provisioners += [$provisioner]' <<<"$config")
  done

  printf "%s\n" "$config" >"$STEPPATH/config/ca.json" # done, write the config
}

main "$@"
