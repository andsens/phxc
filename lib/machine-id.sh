#!/usr/bin/env bash

confirm_machine_id() {
  local hostname=$1 machine_id_var expected_machine_id actual_machine_id
  machine_id_var=MACHINE_IDS_${hostname//-/_}
  expected_machine_id=${!machine_id_var}
  actual_machine_id=$(cat /etc/machine-id)
  if [[ $expected_machine_id != "$actual_machine_id" ]]; then
    error "This script is intended to be run on '%s' (the machine-id '%s' does not match the expected '%s')" \
      "$hostname" "$actual_machine_id" "$expected_machine_id"
    return 1
  fi
  return 0
}
