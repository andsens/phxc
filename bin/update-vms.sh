#!/usr/bin/env bash
# shellcheck source-path=..
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
  source "$PKGROOT/lib/machine-id.sh"
  source "$PKGROOT/lib/vm.sh"

  DOC="update-vms.sh - Bootstrap a VM disk image and replace the current one
Usage:
  update-vms.sh [options] VMNAME:HOSTNAME:DISKPATH...

Options:
  --bootstrapper=VMNAME  Name of the bootstrapper VM [default: Bootstrapper]
"
# docopt parser below, refresh this parser with `docopt.sh update-vms.sh`
# shellcheck disable=2016,1090,1091,2034,2154
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:217}; usage=${DOC:70:60}; digest=f5e38; shorts=('')
longs=(--bootstrapper); argcounts=(1); node_0(){ value __bootstrapper 0; }
node_1(){ value VMNAME_HOSTNAME_DISKPATH a true; }; node_2(){ optional 0; }
node_3(){ optional 2; }; node_4(){ oneormore 1; }; node_5(){ required 3 4; }
node_6(){ required 5; }; cat <<<' docopt_exit() {
[[ -n $1 ]] && printf "%s\n" "$1" >&2; printf "%s\n" "${DOC:70:60}" >&2; exit 1
}'; unset var___bootstrapper var_VMNAME_HOSTNAME_DISKPATH; parse 6 "$@"
local prefix=${DOCOPT_PREFIX:-''}; unset "${prefix}__bootstrapper" \
"${prefix}VMNAME_HOSTNAME_DISKPATH"
eval "${prefix}"'__bootstrapper=${var___bootstrapper:-Bootstrapper}'
if declare -p var_VMNAME_HOSTNAME_DISKPATH >/dev/null 2>&1; then
eval "${prefix}"'VMNAME_HOSTNAME_DISKPATH=("${var_VMNAME_HOSTNAME_DISKPATH[@]}")'
else eval "${prefix}"'VMNAME_HOSTNAME_DISKPATH=()'; fi; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}__bootstrapper" "${prefix}VMNAME_HOSTNAME_DISKPATH"; done
}
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' update-vms.sh`
  eval "$(docopt "$@")"
  source "$PKGROOT/vars.sh"
  confirm_machine_id truenas

  log_forward_to_journald true

  cache_all_vms

  local vmhostdisk vmhost hostnames=()
  for vmhostdisk in "${VMNAME_HOSTNAME_DISKPATH[@]}"; do
    vmhost=${vmhostdisk%:*}
    hostnames+=("${vmhost#*:}")
  done
  local tee=tee mv=mv
  [[ $UID = 0 ]] || tee="sudo tee"
  [[ $UID = 0 ]] || mv="sudo mv"
  # shellcheck disable=2086
  printf -- '#!/usr/bin/env bash\nHOSTNAMES=(%s)\n' "${hostnames[*]}" | \
    $tee "$PKGROOT/bootstrap-vms.args.sh" >/dev/null

  # shellcheck disable=2154
  start_vm "$__bootstrapper"
  # shellcheck disable=2064
  trap "stop_vm \"$__bootstrapper\"" EXIT

  info "Waiting for bootstrapping to complete"
  while [[ -e "$PKGROOT/bootstrap-vms.args.sh" ]]; do
    sleep 1
  done
  info "Bootstrapping completed"
  stop_vm "$__bootstrapper"
  trap "" EXIT

  local vmname hostname diskpath ret=0 latest_imgpath current_imgpath
  for vmhostdisk in "${VMNAME_HOSTNAME_DISKPATH[@]}"; do
    vmname=${vmhostdisk%%:*}
    vmhost=${vmhostdisk%:*}
    hostname=${vmhost#*:}
    diskpath=${vmhostdisk##*:}

    latest_imgpath="$PKGROOT/images/$hostname.raw"
    current_imgpath="$PKGROOT/images/$hostname.current.raw"
    if [[ -e "$latest_imgpath" ]]; then
      info "Image for '%s' found, replacing disk and then renaming to '%s'" "$vmname" "$current_imgpath"
      local res=0
      replace_vm_disk "$vmname" "$latest_imgpath" "$diskpath" || res=$?
      if [[ $res = 0 ]]; then
        $mv "$latest_imgpath" "$current_imgpath"
        info "Successfully replaced disk for '%s'" "$vmname"
      else
        error "Failed to replace disk for '%s'" "$vmname"
        ret=$res
      fi
    else
      error "'%s' did not successfully bootstrap a new image for '%s'" "$__bootstrapper" "$vmname"
      ret=1
    fi
  done
  if [[ $ret = 0 ]]; then
    info "Successfully replaced the disks on all of the specified VMs"
  else
    error "Failed to replace the disks on some VMs"
  fi
  return $ret
}

main "$@"
