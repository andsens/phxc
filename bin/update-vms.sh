#!/usr/bin/env bash
# shellcheck source-path=..
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
  source "$PKGROOT/lib/settings.sh"
  source "$PKGROOT/lib/machine-id.sh"
  source "$PKGROOT/lib/vm.sh"

  DOC="update-vms.sh - Bootstrap a VM disk image and replace the current one
Usage:
  update-vms.sh [options] HOSTNAME...
"
# docopt parser below, refresh this parser with `docopt.sh update-vms.sh`
# shellcheck disable=2016,1090,1091,2034,2154
docopt() { source "$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh" '1.0.0' || {
ret=$?; printf -- "exit %d\n" "$ret"; exit "$ret"; }; set -e
trimmed_doc=${DOC:0:114}; usage=${DOC:70:44}; digest=f1add; shorts=(); longs=()
argcounts=(); node_0(){ value HOSTNAME a true; }; node_1(){ optional ; }
node_2(){ optional 1; }; node_3(){ oneormore 0; }; node_4(){ required 2 3; }
node_5(){ required 4; }; cat <<<' docopt_exit() {
[[ -n $1 ]] && printf "%s\n" "$1" >&2; printf "%s\n" "${DOC:70:44}" >&2; exit 1
}'; unset var_HOSTNAME; parse 5 "$@"; local prefix=${DOCOPT_PREFIX:-''}
unset "${prefix}HOSTNAME"; if declare -p var_HOSTNAME >/dev/null 2>&1; then
eval "${prefix}"'HOSTNAME=("${var_HOSTNAME[@]}")'; else
eval "${prefix}"'HOSTNAME=()'; fi; local docopt_i=1
[[ $BASH_VERSION =~ ^4.3 ]] && docopt_i=2; for ((;docopt_i>0;docopt_i--)); do
declare -p "${prefix}HOSTNAME"; done; }
# docopt parser above, complete command for generating this parser is `docopt.sh --library='"$PKGROOT/.upkg/andsens/docopt.sh/docopt-lib.sh"' update-vms.sh`
  eval "$(docopt "$@")"
  confirm_machine_id truenas

  log_forward_to_journald true

  local bootstrapper_vm
  bootstrapper_vm=$(get_setting "machines[\"$hostname\"].vm")

  cache_all_vms

  # shellcheck disable=2086
  printf -- '#!/usr/bin/env bash\nHOSTNAMES=(%s)\n' "${HOSTNAME[*]}" > "$PKGROOT/bootstrap-vms.args.sh"
  # shellcheck disable=2064
  trap "rm -f \"$PKGROOT/bootstrap-vms.args.sh\"" EXIT

  # shellcheck disable=2154
  start_vm "$bootstrapper_vm"
  # shellcheck disable=2064
  trap "rm -f \"$PKGROOT/bootstrap-vms.args.sh\"; stop_vm \"$bootstrapper_vm\"" EXIT

  info "Waiting for bootstrapping to complete"
  while [[ -e "$PKGROOT/bootstrap-vms.args.sh" ]]; do
    sleep 1
  done
  info "Bootstrapping completed"
  stop_vm "$bootstrapper_vm"
  trap "" EXIT

  local hostname diskpath ret=0 latest_imgpath current_imgpath
  for hostname in "${HOSTNAME[@]}"; do
    vmname=$(get_setting "machines[\"$hostname\"].vm")
    diskpath=$(get_setting "machines[\"$hostname\"].disk")

    latest_imgpath="$PKGROOT/images/$hostname.raw"
    current_imgpath="$PKGROOT/images/$hostname.current.raw"
    if [[ -e "$latest_imgpath" ]]; then
      info "Image for '%s' found, replacing disk and then renaming to '%s'" "$vmname" "$current_imgpath"
      local res=0
      replace_vm_disk "$vmname" "$latest_imgpath" "$diskpath" || res=$?
      if [[ $res = 0 ]]; then
        mv "$latest_imgpath" "$current_imgpath"
        info "Successfully replaced disk for '%s'" "$vmname"
      else
        error "Failed to replace disk for '%s'" "$vmname"
        ret=$res
      fi
    else
      error "'%s' did not successfully bootstrap a new image for '%s'" "$bootstrapper_vm" "$vmname"
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
