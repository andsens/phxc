#!/usr/bin/env bash
# shellcheck source-path=..

get_setting() {
  local path=$1 parent key
  parent=${path%'.'*}
  key=${path##*'.'}
  if yq -re ".$parent | has(\"$key\")" "$PKGROOT/settings.yaml" >/dev/null; then
    yq -re ".$path // empty" "$PKGROOT/settings.yaml"
  else
    type fatal >/dev/null 2>&1 || source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"
    fatal "Unable to find setting path '%s' in %s" "$path" "$PKGROOT/settings.yaml"
    return 1
  fi
}

is_machine_id() {
  local machine expected_machine_ids=()
  for machine in "$@"; do
    expected_machine_ids+=("$(get_setting "machines[\"$machine\"].uuid")")
  done
  if contains_element "$(cat /etc/machine-id)" "${expected_machine_ids[@]}"; then
    return 0
  else
    return 1
  fi
}

get_machine() {
  # shellcheck disable=2016
  yq -re --arg machine_id "$1" '.machines | to_entries[] | select(.value.uuid==$machine_id) | .key' "$PKGROOT/settings.yaml"
}

confirm_machine_id() {
  if ! is_machine_id "$@"; then
    error "This script is intended to be run on %s" "$(join_by , "$@")"
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
