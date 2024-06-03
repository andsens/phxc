#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=/usr/local/lib/upkg
# shellcheck disable=SC1091
source "$PKGROOT/.upkg/records.sh/records.sh"
source "$PKGROOT/workloads/smallstep/commands/paths.sh"

main() {
  local \
    step_issuer_dir=$STEPPATH/step-issuer-provisioner \
    ssh_host_dir=$STEPPATH/ssh-host-provisioner

  local config
  config=$(jq --arg domain "pki.$CLUSTER_DOMAIN" '.dnsNames+=[$domain]' "/var/lib/home-cluster/workloads/smallstep/config/ca.json")

  local name provisioner_names=(step-issuer ssh-host kube-apiserver-client-ca)

  info "Storing and then removing step-issuer, ssh-host, and kube-apiserver-client-ca provisioners"

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
    --public-key="$step_issuer_dir/pub.json" \
    --private-key="$step_issuer_dir/priv.json" \
    --password-file="$step_issuer_dir-password"

  info "Adding ssh-host provisioner key"
  step ca provisioner add ssh-host --type JWK \
    --public-key="$ssh_host_dir/pub.json" \
    --private-key="$ssh_host_dir/priv.json" \
    --password-file="$ssh_host_dir-password"

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
