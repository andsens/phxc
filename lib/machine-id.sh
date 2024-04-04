#!/usr/bin/env bash

is_machine_id() {
  local hostname=$1 machine_id_var expected_machine_id actual_machine_id
  machine_id_var=MACHINE_IDS_${hostname//-/_}
  expected_machine_id=${!machine_id_var}
  actual_machine_id=$(cat /etc/machine-id)
  if [[ $expected_machine_id = "$actual_machine_id" ]]; then
    return 0
  else
    return 1
  fi
}

confirm_machine_id() {
  local hostname=$1
  if ! is_machine_id "$hostname"; then
    error "This script is intended to be run on '%s' (the machine-id '%s' does not match the expected '%s')" \
      "$hostname" "$actual_machine_id" "$expected_machine_id"
    printf "Do you want to continue regardless? [y/N]" >&2
    if ${HOME_CLUSTER_IGNORE_MACHINE_ID:-false}; then
      printf " HOME_CLUSTER_IGNORE_MACHINE_ID=true, continuing...\n" >&2
      return 0
    elif [[ ! -t 1 ]]; then
      printf " stdin is not a tty and HOME_CLUSTER_IGNORE_MACHINE_ID!=true, aborting...\n" >&2
      return 1
    else
      local continue
      read -r continue
      [[ $continue =~ [Yy] ]] || fatal "User aborted operation"
      return 0
    fi
  fi
  return 0
}
