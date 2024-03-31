#!/usr/bin/env bash

CLICMD=cli
[[ $UID = 0 ]] || CLICMD='sudo cli'

cache_all_vms() {
  VMLIST=()
  local line
  while IFS= read -d $'\n' -r line; do
    VMLIST+=("$line")
  done < <($CLICMD -c 'service vm query id,name,status' -m csv | tail -n+2)
}

get_vm_id() {
  : "${VMLIST:?}"
  local name=$1 line vmid vmname vmstatus
  for line in "${VMLIST[@]}"; do
    # shellcheck disable=2034
    IFS=, read -d $'\n' -r vmid vmname vmstatus <<<"$line"
    # shellcheck disable=2153
    if [[ $vmname = "$name" ]]; then
      printf "%s\n" "$vmid"
      return 0
    fi
  done
  error "VM '%s' not found" "$vmname"
  return 1
}

get_vm_status() {
  : "${VMLIST:?}"
  local name=$1 line vmid vmname vmstatus
  for line in "${VMLIST[@]}"; do
    # shellcheck disable=2034
    IFS=, read -d $'\n' -r vmid vmname vmstatus <<<"$line"
    # shellcheck disable=2153
    if [[ $vmname = "$name" ]]; then
      printf "%s\n" "$vmstatus"
      return 0
    fi
  done
  error "VM '%s' not found" "$vmname"
  return 1
}

start_vm() {
  local name=$1 vmid
  if [[ $(get_vm_status "$name") = *RUNNING* ]]; then
    error "Unable to start VM. '%s' is already running" "$name"
    return 1
  fi
  vmid=$(get_vm_id "$name")
  info "Starting VM '%s'" "$name"
  $CLICMD -c "service vm start $vmid"
  cache_all_vms
}

stop_vm() {
  local name=$1 vmid
  if [[ $(get_vm_status "$name") = *STOPPED* ]]; then
    error "Unable to stop VM. '%s' already stopped" "$name"
    return 1
  fi
  vmid=$(get_vm_id "$name")
  info "Stopping VM '%s'" "$name"
  $CLICMD -c "service vm stop $vmid"
  wait_for_vm_shutdown "$name"
}

wait_for_vm_shutdown() {
  local name=$1
  until [[ $(get_vm_status "$name") = *STOPPED* ]]; do
    sleep 5
    cache_all_vms
  done
}

replace_vm_disk() {
  local name=$1 imgpath=$2 diskpath=$3 dd=dd was_started=false
  [[ $UID = 0 ]] || dd='sudo dd'
  # shellcheck disable=2153
  if [[ $(get_vm_status "$name") = *RUNNING* ]]; then
    was_started=true
    stop_vm "$name"
  else
    info "VM '%s' is stopped. It will not be started once replacement has completed." "$name"
  fi

  $dd if="$imgpath" of="$diskpath" bs=$((1024*128)) conv=sparse
  # shellcheck disable=2154
  if $was_started && ! $__no_start; then
    start_vm "$name"
  fi
}
