#!/usr/bin/env bash
# shellcheck source-path=../
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  source "$PKGROOT/lib/common.sh"

  DOC="mount-image.sh - Mount images
Usage:
  bootstrap MACHINE
"
# docopt parser below, refresh this parser with `docopt.sh mount-image.sh`
# shellcheck disable=2016,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:56}; usage=${DOC:30:26}; digest=d852b; shorts=(); longs=()
argcounts=(); node_0(){ value MACHINE a; }; node_1(){ required 0; }; node_2(){
required 1; }; cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:30:26}" >&2; exit 1; }'; unset var_MACHINE; parse 2 "$@"
local prefix=${DOCOPT_PREFIX:-''}; unset "${prefix}MACHINE"
eval "${prefix}"'MACHINE=${var_MACHINE:-}'; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}MACHINE"; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' mount-image.sh`
  eval "$(docopt "$@")"

  local imgpath=$PKGROOT/images/$MACHINE.raw mount_path
  mount_path=$PKGROOT/mnt/$MACHINE
  mkdir -p "$mount_path"
  mount_image "$imgpath" "$mount_path"
  info "image %s mounted at %s, press <ENTER> to unmount" "${imgpath#"$PKGROOT/"}" "${mount_path#"$PKGROOT/"}"
  local _read
  read -rs _read
}

main "$@"
