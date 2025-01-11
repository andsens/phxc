#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=/usr/local/lib/upkg
source "$PKGROOT/.upkg/records.sh/records.sh"

export STEPPATH=/home/step
KUBE_CLIENT_CA_KEY_PATH=$STEPPATH/kube-api-secrets/kube_apiserver_client_ca_key
KUBE_CLIENT_CA_CRT_PATH=$STEPPATH/kube-api-secrets/kube_apiserver_client_ca.crt

main() {
  local config lb_ipv4 lb_ipv6
  lb_ipv4=$(kubectl -n smallstep get svc kube-client-ca-external -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
  lb_ipv6=$(kubectl -n smallstep get svc kube-client-ca-external -o=jsonpath='{.status.loadBalancer.ingress[1].ip}')
  info "Creating CA config"
  config=$(jq \
    --arg uqnodename "${NODENAME%'.local'}" \
    --arg nodename "$NODENAME" \
    --arg ipv4 "$lb_ipv4" \
    --arg ipv6 "$lb_ipv6" \
    --arg domain "pki-kube.$CLUSTER_DOMAIN" '
      .dnsNames+=([$uqnodename, $nodename, $ipv4, $ipv6, $domain] | unique)
    ' "$STEPPATH/config-ro/kube-client-ca.json")
  local ssh_key admin_jwk
  while IFS= read -r -d , ssh_key || [[ -n $ssh_key ]]; do
    admin_jwk=$(step crypto key format --jwk <<<"$ssh_key")
    admin_jwk=$(jq --arg kid "$(step crypto jwk thumbprint <<<"$admin_jwk")" '.kid=$kid' <<<"$admin_jwk")
    config=$(jq --argjson key "$admin_jwk" '.authority.provisioners += [{
      "type": "JWK",
      "name": $key.kid,
      "key": $key,
      "options": { "x509": { "templateFile": "/home/step/templates/admin.tpl" } },
    }]' <<<"$config")
  done <<<"${CLUSTER_ADMIN_SSH_KEYS:?}"

  printf "%s\n" "$config" >"$STEPPATH/config/ca.json"

  local certs_ram_path=$STEPPATH/secrets
  info "Copying kube-client-ca cert & key to RAM backed volume"
  cp "$KUBE_CLIENT_CA_CRT_PATH" "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_CRT_PATH")"
  cp "$KUBE_CLIENT_CA_KEY_PATH" "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_KEY_PATH")"
  chown 1000:1000 "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_CRT_PATH")"
  chown 1000:1000 "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_KEY_PATH")"
}

main "$@"
