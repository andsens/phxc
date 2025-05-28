#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")
source "$PKGROOT/.upkg/records.sh/records.sh"

main() {
  DOC="generate-cluster-settings.sh - Generate a ConfigMap from a cluster.json
Usage:
  generate-cluster-settings.sh

cluster.json lookup order:
1. /boot/phxc/cluster.json
2. \$PKGROOT/cluster.json
"
# docopt parser below, refresh this parser with `docopt.sh generate-cluster-settings.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034
docopt() { local v='2.0.2'; source \
"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh" "$v" || { ret=$?;printf -- "exit \
%d\n" "$ret";exit "$ret";};set -e;trimmed_doc=${DOC:0:189};usage=${DOC:72:37}
digest=fa6d1;options=();node_0(){ return 0;};cat <<<' docopt_exit() { [[ -n $1 \
]] && printf "%s\n" "$1" >&2;printf "%s\n" "${DOC:72:37}" >&2;exit 1;}';local \
varnames=() varname;for varname in "${varnames[@]}"; do unset "var_$varname"
done;parse 0 "$@";return 0;local p=${DOCOPT_PREFIX:-''};for varname in \
"${varnames[@]}"; do unset "$p$varname";done;eval ;local docopt_i=1;[[ \
$BASH_VERSION =~ ^4.3 ]] && docopt_i=2;for ((;docopt_i>0;docopt_i--)); do for \
varname in "${varnames[@]}"; do declare -p "$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh"' generate-cluster-settings.sh`
  eval "$(docopt "$@")"
  local cluster_config_path=/boot/phxc/cluster.json
  [[ -e $cluster_config_path ]] || cluster_config_path=$PKGROOT/cluster.json
  [[ -e $cluster_config_path ]] || fatal "Unable to find cluster.json in /boot/phxc or %s" "$PKGROOT"
  defaults_path=$PKGROOT/lib/defaults/cluster.json
  printf -- '{
    "kind": "ResourceList",
    "items": [{
      "apiVersion": "v1",
      "kind": "ConfigMap",
      "metadata": {
        "name": "cluster-settings"
      },
      "data": {}
  }]}' | jq \
    --argjson defaults "$(cat "$defaults_path")" \
    --argjson settings "$(cat "$cluster_config_path")" \
    '.items[0].data=($defaults * $settings | walk(if type == "array" then join(",") else . end))'
}

main "$@"
