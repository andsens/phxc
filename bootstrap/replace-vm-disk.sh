#!/usr/bin/env bash
# shellcheck source-path=.. disable=2064

set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")
PATH=$("$PKGROOT/.upkg/.bin/path_prepend" "$PKGROOT/.upkg/.bin")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
  source "$PKGROOT/.upkg/orbit-online/collections.sh/collections.sh"

  DOC="replace-vm-disk.sh - Bootstrap k3s cluster images
Usage:
  replace-vm-disk.sh IMGPATH VMNAME DISKPATH

Options:
  -t --tar=PATH  IMGPATH is an archive, the image is located at PATH inside it
"
# docopt parser below, refresh this parser with `docopt.sh replace-vm-disk.sh`
# shellcheck disable=2016,1090,1091,2034
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:190}; usage=${DOC:50:51}; digest=01e23; shorts=(); longs=()
argcounts=(); node_0(){ value IMGPATH a; }; node_1(){ value VMNAME a; }
node_2(){ value DISKPATH a; }; node_3(){ required 0 1 2; }; node_4(){ required 3
}; cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:50:51}" >&2; exit 1; }'; unset var_IMGPATH var_VMNAME \
var_DISKPATH; parse 4 "$@"; local prefix=${DOCOPT_PREFIX:-''}
unset "${prefix}IMGPATH" "${prefix}VMNAME" "${prefix}DISKPATH"
eval "${prefix}"'IMGPATH=${var_IMGPATH:-}'
eval "${prefix}"'VMNAME=${var_VMNAME:-}'
eval "${prefix}"'DISKPATH=${var_DISKPATH:-}'; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}IMGPATH" "${prefix}VMNAME" "${prefix}DISKPATH"; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' replace-vm-disk.sh`
  eval "$(docopt "$@")"

  if [[ $UID != 0 ]]; then
    fatal "Run with sudo"
  fi
  : "${SUDO_UID:?"\$SUDO_UID is not set, run with sudo"}"

  [[ -z $__tar || $(tar tf "$IMGPATH") = *${__tar}* ]] || \
    fatal "'%s' not found/readable or does not contain '%s'" "$IMGPATH" "$__tar"
  [[ -b $DISKPATH ]] || fatal "'%s' is not a block-device" "$DISKPATH"
  local id name status found=false
  while IFS=, read -d $'\n' -r id name status; do
    if [[ $name = "$VMNAME" ]]; then
      found=true
      if [[ $status = *RUNNING* ]]; then
        info "VM '%s' is running, shutting down now" "$VMNAME"
        cli -c "service vm stop $id"
      fi
      break
    fi
  done < <(cli -c 'service vm query id,name,status' -m csv | tail -n+2)
  $found || fatal "Unable to find VM named '%s'" "$VMNAME"
  if [[ -n $__tar ]]; then
    tar -xSOf "$IMGPATH" "$__tar" | dd of="$DISKPATH" bs=$((1024*128)) conv=sparse
  else
    dd if="$$IMGPATH" of="$DISKPATH" bs=$((1024*128)) conv=sparse
  fi
}

main "$@"
