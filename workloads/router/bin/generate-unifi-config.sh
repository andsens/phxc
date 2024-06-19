#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

main() {
  source "$PKGROOT/.upkg/records.sh/records.sh"
  # shellcheck source=workloads/settings/lib/settings-env.sh
  source "$PKGROOT/workloads/settings/lib/settings-env.sh"
  # shellcheck disable=SC2119
  eval_settings

  DOC="generate-unifi-config.sh - Generate config.gateway.json
Usage:
  generate-unifi-config.sh
"
# docopt parser below, refresh this parser with `docopt.sh generate-unifi-config.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034
docopt() { local v='2.0.1'; source \
"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh" "$v" || { ret=$?;printf -- "exit \
%d\n" "$ret";exit "$ret";};set -e;trimmed_doc=${DOC:0:89};usage=${DOC:56:33}
digest=ac04c;options=();node_0(){ return 0;};cat <<<' docopt_exit() { [[ -n $1 \
]] && printf "%s\n" "$1" >&2;printf "%s\n" "${DOC:56:33}" >&2;exit 1;}';local \
varnames=() varname;for varname in "${varnames[@]}"; do unset "var_$varname"
done;parse 0 "$@";return 0;local p=${DOCOPT_PREFIX:-''};for varname in \
"${varnames[@]}"; do unset "$p$varname";done;eval ;local docopt_i=1;[[ \
$BASH_VERSION =~ ^4.3 ]] && docopt_i=2;for ((;docopt_i>0;docopt_i--)); do for \
varname in "${varnames[@]}"; do declare -p "$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh"' generate-unifi-config.sh`
  eval "$(docopt "$@")"

  set_cluster_vars

  local template
  template=$(cat <<'EOF'
{
  "protocols": {
    "bgp": {}
  },
  "service": {
    "dhcp-server": {},
    "dns": {}
  }
}
EOF
  )

  local bgp_config={}
  bgp_config=$(jq --arg rasn "$_ROUTER_ASN_IPV4" '.[$rasn]={"neighbor": {}}' <<<"$bgp_config")
  bgp_config=$(jq --arg rasn "$_ROUTER_ASN_IPV6" '.[$rasn]={"neighbor": {}}' <<<"$bgp_config")
  local node_ip
  for node_ip in "${_NODES_IPV4[@]}"; do
    bgp_config=$(jq --arg rasn "$_ROUTER_ASN_IPV4" --arg casn "$_CLUSTER_ASN" --arg ip "$node_ip" \
      '.[$rasn].neighbor[$ip]={ "remote-as": $casn }' <<<"$bgp_config")
  done
  for node_ip in "${_NODES_IPV6[@]}"; do
    bgp_config=$(jq --arg rasn "$_ROUTER_ASN_IPV6" --arg casn "$_CLUSTER_ASN" --arg ip "$node_ip" --arg emptystr "''" \
      '.[$rasn].neighbor[$ip]={"remote-as": $casn, "address-family":{"ipv6-unicast": $emptystr}}' <<<"$bgp_config")
  done

  local pxe_config
  pxe_config=$(cat <<EOF
if substring (option vendor-class-identifier, 0, 10) = "HTTPClient" {
  option vendor-class-identifier "HTTPClient";
  if option arch = 00:06 or option arch = 00:0f {
    option bootfile-name "http://$CLUSTER_BOOTSERVER_FIXEDIPV4/x86/vmlinuz.efi";
    filename "http://$CLUSTER_BOOTSERVER_FIXEDIPV4/x86/vmlinuz.efi";
  } elsif option arch = 00:07 or option arch = 00:10 {
    option bootfile-name "http://$CLUSTER_BOOTSERVER_FIXEDIPV4/x64/vmlinuz.efi";
    filename "http://$CLUSTER_BOOTSERVER_FIXEDIPV4/x64/vmlinuz.efi";
  } elsif option arch = 00:0a or option arch = 00:12 {
    option bootfile-name "http://$CLUSTER_BOOTSERVER_FIXEDIPV4/arm32/vmlinuz.efi";
    filename "http://$CLUSTER_BOOTSERVER_FIXEDIPV4/arm32/vmlinuz.efi";
  } elsif option arch = 00:0b or option arch = 00:13 {
    option bootfile-name "http://$CLUSTER_BOOTSERVER_FIXEDIPV4/arm64/vmlinuz.efi";
    filename "http://$CLUSTER_BOOTSERVER_FIXEDIPV4/arm64/vmlinuz.efi";
  }
} else {
  next-server $_TFTPD_IPV4;
  if option arch = 00:06 {
    option bootfile-name "x86.efi";
    filename "x86.efi";
  } elsif option arch = 00:07 {
    option bootfile-name "x64.efi";
    filename "x64.efi";
  } elsif option arch = 00:0a {
    option bootfile-name "arm32.efi";
    filename "arm32.efi";
  } elsif option arch = 00:0b {
    option bootfile-name "arm64.efi";
    filename "arm64.efi";
  }
}
EOF
  )
  pxe_config=${pxe_config//'"'/'&quot;'}
  pxe_config=${pxe_config//$'\n'/}

  local dhcp_config
  dhcp_config=$(cat <<EOF
{
  "global-parameters": [
    "option arch code 93 = unsigned integer 16;",
    "${pxe_config}"
  ]
}
EOF
  )

  local dns_config
  dns_config=$(cat <<EOF
{
  "forwarding": {
    "options": [
      "This part needs to be merged with your existing dns options. Unifi does not merge it automatically.",
      "Run: \`ssh ubnt@$CLUSTER_ROUTER_FIXEDIPV4 -- mca-ctrl -t dump-cfg | jq .service.dns.forwarding.options\`",
      "and replace these comment lines with the output (except the 'host-record=unifi' part, which is always appended).",
      "Do keep the server=... line below",
      "server=/$CLUSTER_DOMAIN/$CLUSTER_COREDNS_LB_FIXEDIPV4"
    ],
    "ERROR": "Remove this line once you have followed the guide above"
  }
}
EOF
  )

  local config=$template
  config=$(jq --argjson bgp "$bgp_config" '.protocols.bgp=$bgp' <<<"$config")
  config=$(jq --argjson dhcp "$dhcp_config" '.service["dhcp-server"]=$dhcp' <<<"$config")
  config=$(jq --argjson dns "$dns_config" '.service.dns=$dns' <<<"$config")
  printf "%s\n" "$config"
}

set_cluster_vars() {
  _TFTPD_IPV4=$(
    kubectl get nodes -l "node-role.cluster.local/tftpd=true" -o=jsonpath='{.items[*].status.addresses}' | \
      jq -r '.[] | select(.type=="InternalIP" and (.address | test("^[0-9.]+$"))) | .address'
  )
  _NODES_IPV4=$(
    kubectl get nodes -o=jsonpath='{.items[*].status.addresses}' | \
      jq -r '.[] | select(.type=="InternalIP" and (.address | test("^[0-9.]+$"))) | .address'
  )
  _NODES_IPV6=$(
    kubectl get nodes -o=jsonpath='{.items[*].status.addresses}' | \
      jq -r '.[] | select(.type=="InternalIP" and (.address | test("^[0-9a-f:]+$"))) | .address'
  )
  _CLUSTER_ASN=$(yq -r '.spec.virtualRouters | first | .localASN' "$PKGROOT/workloads/cilium/bgpp.yaml")
  _ROUTER_ASN_IPV4=$(yq -r '[.spec.virtualRouters[].neighbors[] | select(.families | first | .afi=="ipv4")] | first | .peerASN' "$PKGROOT/workloads/cilium/bgpp.yaml")
  _ROUTER_ASN_IPV6=$(yq -r '[.spec.virtualRouters[].neighbors[] | select(.families | first | .afi=="ipv6")] | first | .peerASN' "$PKGROOT/workloads/cilium/bgpp.yaml")
}

main "$@"
