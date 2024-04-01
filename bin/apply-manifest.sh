#!/usr/bin/env bash
# shellcheck source-path=../
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"

  DOC="apply-manifest.sh - Apply a manifests to the cluster
Usage:
  apply-manifest.sh (all|MANIFEST...) [-- kptargs...]

Note:
  MANIFEST is a path relative to /manifests e.g. cert-manager
"
# docopt parser below, refresh this parser with `docopt.sh apply-manifest.sh`
# shellcheck disable=2016,1090,1091,2034,2154
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:182}; usage=${DOC:53:60}; digest=f6ab0; shorts=(); longs=()
argcounts=(); node_0(){ value MANIFEST a true; }; node_1(){ _command all; }
node_2(){ _command __ --; }; node_3(){ _command kptargs kptargs true; }
node_4(){ oneormore 0; }; node_5(){ either 1 4; }; node_6(){ required 5; }
node_7(){ oneormore 3; }; node_8(){ optional 2 7; }; node_9(){ required 6 8; }
node_10(){ required 9; }; cat <<<' docopt_exit() {
[[ -n $1 ]] && printf "%s\n" "$1" >&2; printf "%s\n" "${DOC:53:60}" >&2; exit 1
}'; unset var_MANIFEST var_all var___ var_kptargs; parse 10 "$@"
local prefix=${DOCOPT_PREFIX:-''}; unset "${prefix}MANIFEST" "${prefix}all" \
"${prefix}__" "${prefix}kptargs"
if declare -p var_MANIFEST >/dev/null 2>&1; then
eval "${prefix}"'MANIFEST=("${var_MANIFEST[@]}")'; else
eval "${prefix}"'MANIFEST=()'; fi; eval "${prefix}"'all=${var_all:-false}'
eval "${prefix}"'__=${var___:-false}'
eval "${prefix}"'kptargs=${var_kptargs:-0}'; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}MANIFEST" "${prefix}all" "${prefix}__" "${prefix}kptargs"
done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' apply-manifest.sh`
  eval "$(docopt "$@")"

  # shellcheck disable=2154
  if $all; then
    MANIFEST=(
      networkpolicies
      csi-driver-nfs
      kubernetes-secret-generator
      cert-manager
      cert-manager-issuers
      step-ca
      redis
      docker-registry
    )
  fi
  local manifest
  # shellcheck disable=2153
  for manifest in "${MANIFEST[@]}"; do
    kustomize build --enable-alpha-plugins --enable-exec "$PKGROOT/manifests/$manifest" | \
      kpt live apply - "${kptargs[@]}"
  done
}

main "$@"
