#!/usr/bin/env bash
set -eo pipefail; shopt -s inherit_errexit

# shellcheck disable=2059
_log() { local tpl=$1; shift; printf -- "$tpl\n" "$@" >&2; }
fatal() { _log "$@"; exit 1; }
info() { _log "$@"; }

main() {
  DOC="replace-vm-disk.sh - Replace a VM disk
Usage:
  replace-vm-disk.sh [options] IMGPATH VMNAME DISKPATH

Options:
  -S --no-start  Don't start the VM if it was stopped to replace the disk
"
  [[ $# -gt 3 ]] || fatal "$DOC"
  [[ $# -lt 5 ]] || fatal "$DOC"
  [[ $# -eq 3 || $1 = -S ]] || fatal "$DOC"
  local __no_start=false
  [[ $# -eq 3 ]] || { __no_start=true; shift; }
  local IMGPATH=$1 VMNAME=$2 DISKPATH=$3

  local cli=cli dd=dd
  if [[ $UID != 0 ]]; then
    cli='sudo cli'
    dd='sudo dd'
  fi

  [[ -b $DISKPATH ]] || fatal "'%s' is not a block-device" "$DISKPATH"
  local vmid vmname vmstatus found=false was_started=false
  while IFS=, read -d $'\n' -r vmid vmname vmstatus; do
    # shellcheck disable=2153
    if [[ $vmname = "$VMNAME" ]]; then
      found=true
      if [[ $vmstatus = *RUNNING* ]]; then
        info "VM '%s' is running, shutting down now" "$VMNAME"
        was_started=true
        $cli -c "service vm stop $vmid"
      else
        info "VM '%s' is stopped. It will not be started once replacement has completed." "$VMNAME"
      fi
      break
    fi
  done < <($cli -c 'service vm query id,name,status' -m csv | tail -n+2)
  $found || fatal "Unable to find VM named '%s'" "$VMNAME"
  $dd if="$IMGPATH" of="$DISKPATH" bs=$((1024*128)) conv=sparse
  # shellcheck disable=2154
  if $was_started && ! $__no_start; then
    info "Starting VM '%s'" "$VMNAME"
    $cli -c "service vm start $vmid"
  fi
}

main "$@"
