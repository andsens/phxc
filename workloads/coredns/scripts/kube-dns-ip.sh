#!/usr/bin/env bash
# shellcheck source-path=../../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../..")

main() {
  DOC="generate-kube-dns-ip.sh - Calculate the kube-dns IPs using the svc CIDR
Usage:
  generate-kube-dns-ip.sh
"
# docopt parser below, refresh this parser with `docopt.sh kube-dns-ip.sh`
# shellcheck disable=2016,2086,2317,1090,1091,2034
docopt() { local v='2.0.2'; source \
"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh" "$v" || { ret=$?;printf -- "exit \
%d\n" "$ret";exit "$ret";};set -e;trimmed_doc=${DOC:0:104};usage=${DOC:72:32}
digest=4f644;options=();node_0(){ return 0;};cat <<<' docopt_exit() { [[ -n $1 \
]] && printf "%s\n" "$1" >&2;printf "%s\n" "${DOC:72:32}" >&2;exit 1;}';local \
varnames=() varname;for varname in "${varnames[@]}"; do unset "var_$varname"
done;parse 0 "$@";return 0;local p=${DOCOPT_PREFIX:-''};for varname in \
"${varnames[@]}"; do unset "$p$varname";done;eval ;local docopt_i=1;[[ \
$BASH_VERSION =~ ^4.3 ]] && docopt_i=2;for ((;docopt_i>0;docopt_i--)); do for \
varname in "${varnames[@]}"; do declare -p "$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh"' kube-dns-ip.sh`
  eval "$(docopt "$@")"
  local ipv4 ipv6
  ipv4=$("$PKGROOT/workloads/coredns/scripts/kube-dns-ip.py" "$(kubectl -n kube-system get cm cilium-config -ojsonpath='{.data.ipv4-service-range}')")
  ipv6=$("$PKGROOT/workloads/coredns/scripts/kube-dns-ip.py" "$(kubectl -n kube-system get cm cilium-config -ojsonpath='{.data.ipv6-service-range}')")
  printf -- 'kind: ResourceList
items:
- apiVersion: v1
  kind: ConfigMap
  metadata:
    name: kube-dns-ip
  data:
    ipv4: "%s"
    ipv6: "%s"' "$ipv4" "$ipv6"
}

main "$@"


