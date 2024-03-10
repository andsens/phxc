#!/usr/bin/env bash
# shellcheck source-path=.. disable=2064

set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")
PATH=$("$PKGROOT/.upkg/.bin/path_prepend" "$PKGROOT/.upkg/.bin")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
  source "$PKGROOT/.upkg/orbit-online/collections.sh/collections.sh"

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
  local mount_path mount_pid
  mount_path=$(mktemp -d)
  trap "rmdir \"$mount_path\"" EXIT ERR
  image_mounted "$IMAGEPATH" "$mount_path" & mount_pid=$!
  trap "kill -TERM $mount_pid; rmdir \"$mount_path\"" EXIT ERR
  local mount
  # shellcheck disable=2154
  while read -r -d $'\n' mount; do
    if [[ -d "${SHAREPATH}${mount}" ]]; then
      verbose "Skipped '%s', already exists" "$mount"
    else
      info "Copying '%s'" "$mount"
      cp -ra "${mount_path}${mount}" "${SHAREPATH}${mount}"
    fi
  done < <("${mount_path}${__list_path}")
}

main "$@"
