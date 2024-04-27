#!/usr/bin/env bash
# shellcheck source-path=../
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  source "$PKGROOT/lib/common.sh"

  DOC="settings.sh - Manage settings
Usage:
  settings.sh get PATH
"
# docopt parser below, refresh this parser with `docopt.sh settings.sh`
# shellcheck disable=2016,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:59}; usage=${DOC:30:29}; digest=08c4c; shorts=(); longs=()
argcounts=(); node_0(){ value PATH a; }; node_1(){ _command get; }; node_2(){
required 1 0; }; node_3(){ required 2; }; cat <<<' docopt_exit() {
[[ -n $1 ]] && printf "%s\n" "$1" >&2; printf "%s\n" "${DOC:30:29}" >&2; exit 1
}'; unset var_PATH var_get; parse 3 "$@"; local prefix=${DOCOPT_PREFIX:-''}
unset "${prefix}PATH" "${prefix}get"; eval "${prefix}"'PATH=${var_PATH:-}'
eval "${prefix}"'get=${var_get:-false}'; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}PATH" "${prefix}get"; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' settings.sh`
  DOCOPT_PREFIX=_
  eval "$(docopt "$@")"
  get_setting "$_PATH"
}

main "$@"
