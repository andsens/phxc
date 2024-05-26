#!/usr/bin/env bash
# shellcheck source-path=..

is_machine_id() {
  local machine machine_uuid_var expected_machine_ids=()
  for machine in "$@"; do
    machine_uuid_var=MACHINES_${machine^^}_UUID
    expected_machine_ids+=("${!machine_uuid_var}")
  done
  if contains_element "$(cat /etc/machine-id)" "${expected_machine_ids[@]}"; then
    return 0
  else
    return 1
  fi
}

get_machine() {
  # shellcheck disable=2016
  yq -re --arg machine_id "$1" '.machines | to_entries[] | select(.value.uuid==$machine_id) | .key' "$PKGROOT/home-cluster.yaml"
}

confirm_machine_id() {
  if ! is_machine_id "$@"; then
    error "This script is intended to be run on %s" "$(join_by , "$@")"
    printf "Do you want to continue regardless? [y/N]" >&2
    if ${HOME_CLUSTER_IGNORE_MACHINE_ID:-false}; then
      printf " HOME_CLUSTER_IGNORE_MACHINE_ID=true, continuing...\n" >&2
      return 0
    elif [[ ! -t 1 ]]; then
      printf "stdin is not a tty and HOME_CLUSTER_IGNORE_MACHINE_ID!=true, aborting...\n" >&2
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
