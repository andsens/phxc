#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

main() {
  local settings_path=$1 dest_dir=$2
  local mac node
  rm -f "$dest_dir"/*.json
  # shellcheck disable=SC2016
  for node in $(yq -c '.nodes[]' "$settings_path"); do
    ! mac=$(yq -re '.mac' <<<"$node") || printf "%s\n" "$node" >"$dest_dir/${mac,,}.json"
  done
}

main "$@"
