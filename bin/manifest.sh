#!/usr/bin/env bash
# shellcheck source-path=../
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"

  DOC="apply-manifest.sh - Manage manifests
Usage:
  manifest.sh apply (all|MANIFEST...) [-- kptargs...]
  manifest.sh build (all|MANIFEST...)

Note:
  MANIFEST is a path relative to /manifests e.g. cert-manager
"
# docopt parser below, refresh this parser with `docopt.sh manifest.sh`
# shellcheck disable=2016,1090,1091,2034,2154
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:204}; usage=${DOC:37:98}; digest=e8b68; shorts=(); longs=()
argcounts=(); node_0(){ value MANIFEST a true; }; node_1(){ _command apply; }
node_2(){ _command all; }; node_3(){ _command __ --; }; node_4(){
_command kptargs kptargs true; }; node_5(){ _command build; }; node_6(){
oneormore 0; }; node_7(){ either 2 6; }; node_8(){ required 7; }; node_9(){
oneormore 4; }; node_10(){ optional 3 9; }; node_11(){ required 1 8 10; }
node_12(){ required 5 8; }; node_13(){ either 11 12; }; node_14(){ required 13
}; cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:37:98}" >&2; exit 1; }'; unset var_MANIFEST var_apply \
var_all var___ var_kptargs var_build; parse 14 "$@"
local prefix=${DOCOPT_PREFIX:-''}; unset "${prefix}MANIFEST" "${prefix}apply" \
"${prefix}all" "${prefix}__" "${prefix}kptargs" "${prefix}build"
if declare -p var_MANIFEST >/dev/null 2>&1; then
eval "${prefix}"'MANIFEST=("${var_MANIFEST[@]}")'; else
eval "${prefix}"'MANIFEST=()'; fi; eval "${prefix}"'apply=${var_apply:-false}'
eval "${prefix}"'all=${var_all:-false}'; eval "${prefix}"'__=${var___:-false}'
eval "${prefix}"'kptargs=${var_kptargs:-0}'
eval "${prefix}"'build=${var_build:-false}'; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}MANIFEST" "${prefix}apply" "${prefix}all" "${prefix}__" \
"${prefix}kptargs" "${prefix}build"; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' manifest.sh`
  eval "$(docopt "$@")"

  # shellcheck disable=2154
  if $all; then
    MANIFEST=(
      cilium
      networkpolicies
      csi-driver-nfs
      kubernetes-secret-generator
      cert-manager
      cert-manager-issuers
      step-ca
      redis
      docker-registry
      etcd
      coredns
      external-dns
    )
  fi
  local manifest_name manifest_data
  # shellcheck disable=2153
  for manifest_name in "${MANIFEST[@]}"; do
    manifest_data=$(kustomize build --enable-alpha-plugins --enable-exec "$PKGROOT/manifests/$manifest_name")
    # shellcheck disable=2154
    if $apply; then
      kpt live apply - "${kptargs[@]}" <<<"$manifest_data"
    elif $build; then
      printf "%s\n" "$manifest_data"
    fi
  done
}

main "$@"
