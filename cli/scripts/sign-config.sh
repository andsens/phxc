#!/usr/bin/env bash
# shellcheck source-path=../..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")
# Special handling when called from parent package
[[ -d $PKGROOT/.upkg ]] || PKGROOT=$(realpath "$PKGROOT/..")
source "$PKGROOT/.upkg/records.sh/records.sh"

main() {
  DOC="sign-config - Sign config files using an SSH key
Usage:
  sign-config [-c=PATH] CONFIG...

Options:
  -c --clustercfg PATH  Path to cluster.json [default: /efi/phxc/cluster.json]
"
# docopt parser below, refresh this parser with `docopt.sh sign-config`
# shellcheck disable=2016,2086,2317,1090,1091,2034,2154
docopt() { local v='2.0.2'; source \
"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh" "$v" || { ret=$?;printf -- "exit \
%d\n" "$ret";exit "$ret";};set -e;trimmed_doc=${DOC:0:178};usage=${DOC:49:40}
digest=25508;options=('-c --clustercfg 1');node_0(){ value __clustercfg 0;}
node_1(){ value CONFIG a true;};node_2(){ optional 0;};node_3(){ repeatable 1;}
node_4(){ sequence 2 3;};cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" \
"$1" >&2;printf "%s\n" "${DOC:49:40}" >&2;exit 1;}';local \
varnames=(__clustercfg CONFIG) varname;for varname in "${varnames[@]}"; do
unset "var_$varname";done;parse 4 "$@";local p=${DOCOPT_PREFIX:-''};for \
varname in "${varnames[@]}"; do unset "$p$varname";done;if declare -p \
var_CONFIG >/dev/null 2>&1; then eval $p'CONFIG=("${var_CONFIG[@]}")';else
eval $p'CONFIG=()';fi;eval $p'__clustercfg=${var___clustercfg:-/efi/phxc/clust'\
'er.json};';local docopt_i=1;[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2;for \
((;docopt_i>0;docopt_i--)); do for varname in "${varnames[@]}"; do declare -p \
"$p$varname";done;done;}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/docopt-lib-v$v/docopt-lib.sh"' sign-config`
  eval "$(docopt "$@")"

  # shellcheck disable=SC2154
  [[ -e $__clustercfg ]] || fatal "cluster.json not found at %s" "$__clustercfg"
  local test_tmp test_admin_ssh_key admin_ssh_key
  test_tmp=$(mktemp -d --suffix '-phxc-sign-config')
  # shellcheck disable=SC2064
  trap "rm -rf \"$test_tmp\"" EXIT
  touch "$test_tmp/test"
  while IFS= read -r -d $'\n' test_admin_ssh_key; do
    if ssh-keygen -Y sign -f <(printf "%s" "$test_admin_ssh_key") -n file "$test_tmp/test" 2>/dev/null; then
      admin_ssh_key=$test_admin_ssh_key
      break
    fi
  done < <(jq -r '.admin.sshKeys[]' "$__clustercfg")
  [[ -n $admin_ssh_key ]] || fatal "No keys specified in %s are available to sign with" "$__clustercfg"

  for config_path in "${CONFIG[@]}"; do
    rm -fv "$config_path.sig"
    ssh-keygen -Y sign -f <(printf "%s" "$admin_ssh_key") -n file "$config_path"
  done
}

main "$@"
