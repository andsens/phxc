#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit
# shellcheck disable=SC1091
source /usr/local/lib/upkg/.upkg/records.sh/records.sh

KUBE_CLIENT_CA_KEY_PATH=$STEPPATH/kube-api-secrets/kube_apiserver_client_ca_key
KUBE_CLIENT_CA_CRT_PATH=$STEPPATH/kube-api-secrets/kube_apiserver_client_ca.crt

main() {
  local lb_ipv4 lb_ipv6 admin_jwk
  lb_ipv4=$(kubectl -n smallstep get svc kube-apiserver-client-ca-external -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
  lb_ipv6=$(kubectl -n smallstep get svc kube-apiserver-client-ca-external -o=jsonpath='{.status.loadBalancer.ingress[1].ip}')
  admin_jwk=$(step crypto key format --jwk <<<"${CLUSTER_ADMIN_SSH_KEY:?}")
  admin_jwk=$(jq --arg kid "$(step crypto jwk thumbprint <<<"$admin_jwk")" '.kid=$kid' <<<"$admin_jwk")
  info "Creating CA config"
  jq \
    --arg uqnodename "${NODENAME%'.local'}" \
    --arg nodename "$NODENAME" \
    --arg ipv4 "$lb_ipv4" \
    --arg ipv6 "$lb_ipv6" \
    --arg domain "pki-kube.$CLUSTER_DOMAIN" \
    --argjson admin_jwk "$admin_jwk" '
      .dnsNames+=([$uqnodename, $nodename, $ipv4, $ipv6, $domain] | unique) |
      (.authority.provisioners[] | select(.name=="admin") | .key) |= $admin_jwk
    ' "$STEPPATH/config-ro/kube-apiserver-client-ca.json" >"$STEPPATH/config/ca.json"

  local certs_ram_path=$STEPPATH/secrets
  info "Copying kube-apiserver-client-ca cert & key to RAM backed volume"
  cp "$KUBE_CLIENT_CA_CRT_PATH" "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_CRT_PATH")"
  cp "$KUBE_CLIENT_CA_KEY_PATH" "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_KEY_PATH")"
  chown step:step "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_CRT_PATH")"
  chown step:step "$certs_ram_path/$(basename "$KUBE_CLIENT_CA_KEY_PATH")"
}

main "$@"
