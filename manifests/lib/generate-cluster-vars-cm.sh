#!/usr/bin/env bash
# shellcheck source-path=../../
set -eo pipefail; shopt -s inherit_errexit
until [[ -e $PKGROOT/upkg.json || $PKGROOT = '/' ]]; do PKGROOT=$(dirname "${PKGROOT:-$(realpath "${BASH_SOURCE[0]}")}"); done

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
  source "$PKGROOT/.upkg/orbit-online/collections.sh/collections.sh"

  DOC="generate-vars-cluster-cm.sh - Generate a ConfigMap from /vars.sh
Usage:
  generate-vars-cluster-cm.sh
"
# docopt parser below, refresh this parser with `docopt.sh generate-cluster-vars-cm.sh`
# shellcheck disable=2016,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:101}; usage=${DOC:65:36}; digest=f53eb; shorts=(); longs=()
argcounts=(); node_0(){ required ; }; node_1(){ required 0; }
cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:65:36}" >&2; exit 1; }'; unset ; parse 1 "$@"; return 0
local prefix=${DOCOPT_PREFIX:-''}; unset ; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p ; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' generate-cluster-vars-cm.sh`
  eval "$(docopt "$@")"
  local existing_varnames='' varnames=() varname
  existing_varnames=$(declare | grep '^[[:alpha:]].*=' | cut -d= -f1 | sort)
  source "$PKGROOT/vars.sh"
  readarray -t varnames < <(comm -13 <(printf "%s" "$existing_varnames") <(declare | grep '^[[:alpha:]].*=' | cut -d= -f1 | sort))
  printf 'apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-vars
  annotations:
    config.kubernetes.io/local-config: "true"
data:
'
  for varname in "${varnames[@]}"; do
    if [[ $(declare -p "$varname") = 'declare -- '* ]]; then
      printf "  %s: %s\n" "$varname" "$(jq --arg v "${!varname}" '.val=$v | .val' <<<"{}")"
    fi
  done
}

main "$@"
