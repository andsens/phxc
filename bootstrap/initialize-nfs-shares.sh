#!/usr/bin/env bash
# shellcheck source-path=.. disable=2064

set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")
PATH=$("$PKGROOT/.upkg/.bin/path_prepend" "$PKGROOT/.upkg/.bin")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
  source "$PKGROOT/.upkg/orbit-online/collections.sh/collections.sh"
  source "$PKGROOT/bootstrap/lib/mount.sh"

  DOC="initialize-nfs-shares.sh - Copy paths from a raw image based on a mount list
Existing paths will not be overwritten

Usage:
  initialize-nfs-shares [options] IMAGEPATH SHAREPATH

Options:
  -l --list-path=PATH  Path to file on raw image that lists the mount paths
                       [default: /var/lib/fai/nfs-mounts]
"
# docopt parser below, refresh this parser with `docopt.sh initialize-nfs-shares.sh`
# shellcheck disable=2016,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:321}; usage=${DOC:117:60}; digest=127a3; shorts=(-l)
longs=(--list-path); argcounts=(1); node_0(){ value __list_path 0; }; node_1(){
value IMAGEPATH a; }; node_2(){ value SHAREPATH a; }; node_3(){ optional 0; }
node_4(){ optional 3; }; node_5(){ required 4 1 2; }; node_6(){ required 5; }
cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:117:60}" >&2; exit 1; }'; unset var___list_path \
var_IMAGEPATH var_SHAREPATH; parse 6 "$@"; local prefix=${DOCOPT_PREFIX:-''}
unset "${prefix}__list_path" "${prefix}IMAGEPATH" "${prefix}SHAREPATH"
eval "${prefix}"'__list_path=${var___list_path:-/var/lib/fai/nfs-mounts}'
eval "${prefix}"'IMAGEPATH=${var_IMAGEPATH:-}'
eval "${prefix}"'SHAREPATH=${var_SHAREPATH:-}'; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}__list_path" "${prefix}IMAGEPATH" "${prefix}SHAREPATH"
done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' initialize-nfs-shares.sh`
  eval "$(docopt "$@")"

  if [[ $UID != 0 ]]; then
    fatal "Run with sudo"
  fi
  : "${SUDO_UID:?"\$SUDO_UID is not set, run with sudo"}"

  mount_image "$IMAGEPATH"
  local mount src dest
  # shellcheck disable=2031,2154
  while read -r -d $'\n' mount; do
    src=${MOUNT_PATH}${mount}
    dest=${SHAREPATH}${mount}
    if [[ -d "$dest" ]]; then
      verbose "Skipped '%s', already exists" "$mount"
    elif [[ ! -d "$src" ]]; then
      warning "'%s' does not exist on the image"
    else
      info "Copying '%s'" "$mount"
      mkdir -p "$(dirname "$dest")"
      cp -ra "$src" "$dest"
    fi
  done <"${MOUNT_PATH}${__list_path}"
}

main "$@"
