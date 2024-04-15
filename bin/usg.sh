#!/usr/bin/env bash
# shellcheck source-path=../
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")
source "$PKGROOT/vars.sh"
ssh="ssh -o ControlMaster=auto -o ControlPath=~/.ssh/%r@%h:%p -o ControlPersist=3s"

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
  source "$PKGROOT/lib/machine-id.sh"

  DOC="usg.sh - Manage a Unifi Security Gateway setup
Usage:
  usg.sh get (ck|usg)
  usg.sh set ck [CFGGWPATH]
  usg.sh enable-bgp
  usg.sh clear-bgp

Commands:
  get:        Retrieve config.gateway.json from either the Cloud Key or the USG
  set:        Upload stdin to config.gateway.json on the Cloud Key
  enable-bgp: Setup/update BGP in config.gateway.json on the Cloud Key
  clear-bgp:  Remove all BGP config in config.gateway.json on the Cloud Key
"
# docopt parser below, refresh this parser with `docopt.sh usg.sh`
# shellcheck disable=2016,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:447}; usage=${DOC:47:95}; digest=74987; shorts=(); longs=()
argcounts=(); node_0(){ value CFGGWPATH a; }; node_1(){ _command get; }
node_2(){ _command ck; }; node_3(){ _command usg; }; node_4(){ _command set; }
node_5(){ _command enable_bgp enable-bgp; }; node_6(){
_command clear_bgp clear-bgp; }; node_7(){ either 2 3; }; node_8(){ required 7
}; node_9(){ required 1 8; }; node_10(){ optional 0; }; node_11(){
required 4 2 10; }; node_12(){ required 5; }; node_13(){ required 6; }
node_14(){ either 9 11 12 13; }; node_15(){ required 14; }
cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:47:95}" >&2; exit 1; }'; unset var_CFGGWPATH var_get \
var_ck var_usg var_set var_enable_bgp var_clear_bgp; parse 15 "$@"
local prefix=${DOCOPT_PREFIX:-''}; unset "${prefix}CFGGWPATH" "${prefix}get" \
"${prefix}ck" "${prefix}usg" "${prefix}set" "${prefix}enable_bgp" \
"${prefix}clear_bgp"; eval "${prefix}"'CFGGWPATH=${var_CFGGWPATH:-}'
eval "${prefix}"'get=${var_get:-false}'; eval "${prefix}"'ck=${var_ck:-false}'
eval "${prefix}"'usg=${var_usg:-false}'; eval "${prefix}"'set=${var_set:-false}'
eval "${prefix}"'enable_bgp=${var_enable_bgp:-false}'
eval "${prefix}"'clear_bgp=${var_clear_bgp:-false}'; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}CFGGWPATH" "${prefix}get" "${prefix}ck" "${prefix}usg" \
"${prefix}set" "${prefix}enable_bgp" "${prefix}clear_bgp"; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' usg.sh`
  eval "$(docopt "$@")"

  # shellcheck disable=2154
  if $get && $ck; then
    get_ck_config
  elif $get && $usg; then
    get_usg_config
  elif $set && $ck; then
    if [[ -n $CFGGWPATH ]]; then
      set_ck_config "$(cat "$CFGGWPATH")"
    else
      set_ck_config "$(cat)"
    fi
  elif $enable_bgp; then
    local config node_ipv4_addrs node_ipv4 bgp_asn=64512
    config=$(get_config)
    node_ipv4_addrs=$(kubectl get nodes -ojson | jq -r '.items[].status.addresses[] | select(.type=="InternalIP" and (.address | split(".") | length) == 4) | .address')
    for node_ipv4 in $node_ipv4_addrs; do
      config=$(jq \
        --arg bgp_asn "$bgp_asn" --arg NODE_IPV4 "$node_ipv4" \
        ".protocols.bgp[\$bgp_asn].neighbor[\$NODE_IPV4] = {\"remote-as\": \$bgp_asn, \"address-family\": {\"ipv6-unicast\": \"''\"}}" <<<"$config")
    done
    set_ck_config "$(jq --indent 2 . <<<"$config")"
  elif $clear_bgp; then
    config=$(jq 'del(.protocols.bgp)' <<<"$config")
  fi
}

get_config() {
  get_ck_config 2>/dev/null || printf "{}\n"
}

get_ck_config() {
  $ssh "$UNIFI_CLOUDKEY_SSH_ADDR" -- cat /srv/unifi/data/sites/$UNIFI_SITE/config.gateway.json
}

get_usg_config() {
  $ssh "$UNIFI_USG_SSH_ADDR" -- mca-ctrl -t dump-cfg
}

set_ck_config() {
  local config=$1
  $ssh "$UNIFI_CLOUDKEY_SSH_ADDR" -- mkdir -p /srv/unifi/data/sites/$UNIFI_SITE
  $ssh "$UNIFI_CLOUDKEY_SSH_ADDR" -- tee /srv/unifi/data/sites/$UNIFI_SITE/config.gateway.json <<<"$config" >/dev/null
}

main "$@"
