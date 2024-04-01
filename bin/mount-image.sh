#!/usr/bin/env bash
# shellcheck source-path=../
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
  source "$PKGROOT/lib/machine-id.sh"
  source "$PKGROOT/lib/mount.sh"

  DOC="mount-image.sh - Mount images
Usage:
  bootstrap HOSTNAME
"
# docopt parser below, refresh this parser with `docopt.sh mount-image.sh`
# shellcheck disable=2016,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:57}; usage=${DOC:30:27}; digest=78cca; shorts=(); longs=()
argcounts=(); node_0(){ value HOSTNAME a; }; node_1(){ required 0; }; node_2(){
required 1; }; cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:30:27}" >&2; exit 1; }'; unset var_HOSTNAME; parse 2 "$@"
local prefix=${DOCOPT_PREFIX:-''}; unset "${prefix}HOSTNAME"
eval "${prefix}"'HOSTNAME=${var_HOSTNAME:-}'; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}HOSTNAME"; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' mount-image.sh`
  eval "$(docopt "$@")"

  local imgpath=$PKGROOT/images/$HOSTNAME.raw mount_path
  mount_path=$PKGROOT/mnt/$HOSTNAME
  mkdir -p "$mount_path"
  mount_image "$imgpath" "$mount_path"
  info "image %s mounted at %s, press <ENTER> to unmount" "${imgpath#"$PKGROOT/"}" "${mount_path#"$PKGROOT/"}"
  local _read
  read -rs _read
}

main "$@"
