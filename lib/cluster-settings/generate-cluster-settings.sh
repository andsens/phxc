#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")

main() {
  source "$PKGROOT/.upkg/records.sh/records.sh"

  DOC="generate-cluster-settings.sh - Generate a ConfigMap from a cluster.yaml
Usage:
  generate-cluster-settings.sh

cluster.yaml lookup order:
1. /etc/phxc/cluster.yaml
2. \$PKGROOT/cluster.yaml
"
# docopt parser below, refresh this parser with `docopt.sh generate-cluster-settings.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034
docopt() { local v='2.0.2'; source \
"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh" "$v" || { ret=$?;printf -- "exit \
%d\n" "$ret";exit "$ret";};set -e;trimmed_doc=${DOC:0:188};usage=${DOC:72:37}
digest=f9956;options=();node_0(){ return 0;};cat <<<' docopt_exit() { [[ -n $1 \
]] && printf "%s\n" "$1" >&2;printf "%s\n" "${DOC:72:37}" >&2;exit 1;}';local \
varnames=() varname;for varname in "${varnames[@]}"; do unset "var_$varname"
done;parse 0 "$@";return 0;local p=${DOCOPT_PREFIX:-''};for varname in \
"${varnames[@]}"; do unset "$p$varname";done;eval ;local docopt_i=1;[[ \
$BASH_VERSION =~ ^4.3 ]] && docopt_i=2;for ((;docopt_i>0;docopt_i--)); do for \
varname in "${varnames[@]}"; do declare -p "$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh"' generate-cluster-settings.sh`
  eval "$(docopt "$@")"
  local cluster_yaml_path=/etc/phxc/cluster.yaml
  [[ -e $cluster_yaml_path ]] || cluster_yaml_path=$PKGROOT/cluster.yaml
  [[ -e $cluster_yaml_path ]] || fatal "Unable to find cluster.yaml in /etc/phxc or %s" "$PKGROOT"
  defaults_path=$PKGROOT/lib/defaults/cluster.yaml
  # shellcheck disable=SC2016
  printf -- 'kind: ResourceList
items:
- apiVersion: v1
  kind: ConfigMap
  metadata:
    name: cluster-settings
  data:' | yq -y --indentless \
    --argjson defaults "$(yq . "$defaults_path")" \
    --argjson settings "$(yq . "$cluster_yaml_path")" \
    '.items[0].data=($defaults * $settings | walk(if type == "array" then join(",") else . end))'
}

main "$@"
