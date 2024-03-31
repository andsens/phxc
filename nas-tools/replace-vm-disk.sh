#!/usr/bin/env bash
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")

main() {
  source "$PKGROOT/records.sh"
  source "$PKGROOT/common.sh"

  DOC="replace-vm-disk.sh - Replace a VM disk in TrueNAS
Usage:
  replace-vm-disk.sh [options] VMNAME IMGPATH DISKPATH

Options:
  -S --no-start  Don't start the VM if it was stopped to replace the disk
"
# docopt parser below, refresh this parser with `docopt.sh replace-vm-disk.sh`
# shellcheck disable=2016,1090,1091,2034
docopt() { source "$PKGROOT/docopt-lib-v1.0.0.sh" '1.0.0' || { ret=$?
printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e; trimmed_doc=${DOC:0:195}
usage=${DOC:50:61}; digest=ea0c5; shorts=(-S); longs=(--no-start); argcounts=(0)
node_0(){ switch __no_start 0; }; node_1(){ value VMNAME a; }; node_2(){
value IMGPATH a; }; node_3(){ value DISKPATH a; }; node_4(){ optional 0; }
node_5(){ optional 4; }; node_6(){ required 5 1 2 3; }; node_7(){ required 6; }
cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:50:61}" >&2; exit 1; }'; unset var___no_start var_VMNAME \
var_IMGPATH var_DISKPATH; parse 7 "$@"; local prefix=${DOCOPT_PREFIX:-''}
unset "${prefix}__no_start" "${prefix}VMNAME" "${prefix}IMGPATH" \
"${prefix}DISKPATH"; eval "${prefix}"'__no_start=${var___no_start:-false}'
eval "${prefix}"'VMNAME=${var_VMNAME:-}'
eval "${prefix}"'IMGPATH=${var_IMGPATH:-}'
eval "${prefix}"'DISKPATH=${var_DISKPATH:-}'; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}__no_start" "${prefix}VMNAME" "${prefix}IMGPATH" \
"${prefix}DISKPATH"; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/docopt-lib-v1.0.0.sh"' replace-vm-disk.sh`
  eval "$(docopt "$@")"
  cache_all_vms

  # shellcheck disable=2153
  replace_vm_disk "$VMNAME" "$IMGPATH" "$DISKPATH"
}

main "$@"
