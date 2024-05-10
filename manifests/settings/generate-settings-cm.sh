#!/usr/bin/env bash
# shellcheck source-path=../../
set -Eeo pipefail; shopt -s inherit_errexit
until [[ -e $PKGROOT/upkg.json || $PKGROOT = '/' ]]; do PKGROOT=$(dirname "${PKGROOT:-$(realpath "${BASH_SOURCE[0]}")}"); done

main() {
  source "$PKGROOT/.upkg/records.sh/records.sh"

  DOC="generate-settings-cm.sh - Generate a ConfigMap from /config/home-cluster.yaml
Usage:
  generate-settings-cm.sh
"
# docopt parser below, refresh this parser with `docopt.sh generate-settings-cm.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/docopt-lib.sh/docopt-lib.sh" '2.0.0a3' || {
ret=$?;printf -- "exit %d\n" "$ret";exit "$ret";};set -e
trimmed_doc=${DOC:0:110};usage=${DOC:78:32};digest=5ed25;options=();node_0(){
return 0;};cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:78:32}" >&2;exit 1;}';local varnames=() varname;for \
varname in "${varnames[@]}"; do unset "var_$varname";done;parse 0 "$@";return 0
local p=${DOCOPT_PREFIX:-''};for varname in "${varnames[@]}"; do unset \
"$p$varname";done;eval ;local docopt_i=1;[[ $BASH_VERSION =~ ^4.3 ]] && \
docopt_i=2;for ((;docopt_i>0;docopt_i--)); do for varname in "${varnames[@]}"; \
do declare -p "$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib.sh/docopt-lib.sh"' generate-settings-cm.sh`
  eval "$(docopt "$@")"
  printf -- 'kind: ResourceList
items:
- apiVersion: v1
  kind: ConfigMap
  metadata:
    name: settings
  data:
' | yq -y --indentless --argjson settings "$(yq . "$PKGROOT/config/home-cluster.yaml")" ".items[0].data=\$settings"

}

main "$@"
