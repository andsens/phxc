#!/usr/bin/env bash
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")

main() {
  source "$PKGROOT/records.sh"
  source "$PKGROOT/common.sh"

  DOC="update-vms.sh - Bootstrap a VM disk image and replace the current one
Usage:
  update-vms.sh [options] VMNAME:HOSTNAME:DISKPATH...

Options:
  --bootstrapper=VMNAME  Name of the bootstrapper VM [default: Bootstrapper]
  --varspath=PATH        Path to vars.sh [default: \$PKGROOT/../vars.sh]
"
# docopt parser below, refresh this parser with `docopt.sh update-vms.sh`
# shellcheck disable=2016,1090,1091,2034,2154
docopt() { source "$PKGROOT/docopt-lib-v1.0.0.sh" '1.0.0' || { ret=$?
printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e; trimmed_doc=${DOC:0:289}
usage=${DOC:70:60}; digest=21917; shorts=('' '')
longs=(--varspath --bootstrapper); argcounts=(1 1); node_0(){ value __varspath 0
}; node_1(){ value __bootstrapper 1; }; node_2(){
value VMNAME_HOSTNAME_DISKPATH a true; }; node_3(){ optional 0 1; }; node_4(){
optional 3; }; node_5(){ oneormore 2; }; node_6(){ required 4 5; }; node_7(){
required 6; }; cat <<<' docopt_exit() { [[ -n $1 ]] && printf "%s\n" "$1" >&2
printf "%s\n" "${DOC:70:60}" >&2; exit 1; }'; unset var___varspath \
var___bootstrapper var_VMNAME_HOSTNAME_DISKPATH; parse 7 "$@"
local prefix=${DOCOPT_PREFIX:-''}; unset "${prefix}__varspath" \
"${prefix}__bootstrapper" "${prefix}VMNAME_HOSTNAME_DISKPATH"
eval "${prefix}"'__varspath=${var___varspath:-'"'"'$PKGROOT/../vars.sh'"'"'}'
eval "${prefix}"'__bootstrapper=${var___bootstrapper:-Bootstrapper}'
if declare -p var_VMNAME_HOSTNAME_DISKPATH >/dev/null 2>&1; then
eval "${prefix}"'VMNAME_HOSTNAME_DISKPATH=("${var_VMNAME_HOSTNAME_DISKPATH[@]}")'
else eval "${prefix}"'VMNAME_HOSTNAME_DISKPATH=()'; fi; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}__varspath" "${prefix}__bootstrapper" \
"${prefix}VMNAME_HOSTNAME_DISKPATH"; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/docopt-lib-v1.0.0.sh"' update-vms.sh`
  eval "$(docopt "$@")"
  cache_all_vms

  [[ $__varspath != "\$PKGROOT/../vars.sh" ]] || __varspath=$(realpath "$PKGROOT/../vars.sh")
  # shellcheck source=../vars.sh
  source "$__varspath"

  local vmhostdisk vmhost hostnames=()
  for vmhostdisk in "${VMNAME_HOSTNAME[@]}"; do
    vmhost=${vmhostdisk%:*}
    hostnames+=("${vmhost#*:}")
  done
  printf -- '#!/usr/bin/env bash
HOSTNAMES="%s"
SHUTDOWN=true
' "$BOOTSTRAPPER_GIT_REMOTE" "$BOOTSTRAPPER_GIT_DEPLOY_KEY" "${hostnames[*]}" > "$BOOTSTRAPPER_NFS_SHARE/bootstrap-vms.args.sh"

  # shellcheck disable=2154
  start_vm "$__bootstrapper"

  info "Waiting for '%s' to finish bootstrapping" "$__bootstrapper"
  wait_for_vm_shutdown "$__bootstrapper"
  info "'%s' has completed bootstrapping and shut down again" "$__bootstrapper"

  local vmname hostname diskpath ret latest_imgpath current_imgpath
  for vmhostdisk in "${VMNAME_HOSTNAME[@]}"; do
    vmname=${vmhostdisk%%:*}
    vmhost=${vmhostdisk%:*}
    hostname=${vmhost#*:}
    diskpath=${vmhostdisk##*:}

    latest_imgpath="$BOOTSTRAPPER_NFS_SHARE/images/$hostname.latest.raw"
    current_imgpath="$BOOTSTRAPPER_NFS_SHARE/images/$hostname.current.raw"
    if [[ -e "$latest_imgpath" ]]; then
      info "Image for '%s' found, replacing disk and then renaming to '%s'" "$vmname" "$current_imgpath"
      local res=0
      replace_vm_disk "$vmname" "$latest_imgpath" "$diskpath" || res=$?
      if [[ $res = 0 ]]; then
        mv "$latest_imgpath" "$current_imgpath"
      else
        error "Failed to replace disk for '%s'" "$vmname"
        ret=$res
      fi
    else
      error "'%s' did not successfully bootstrap a new image for '%s'" "$__bootstrapper" "$vmname"
      ret=1
    fi
  done
  [[ $ret = 0 ]] || error "Failed to replace the disks on some VMs"
  ! ${SHUTDOWN:-false} || systemctl halt
  return $ret
}

main "$@"
