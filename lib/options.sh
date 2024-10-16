#!/usr/bin/env bash

select_options() {
  local prompt=$1 done_option=$2 option_count selected_option
  shift; shift
  local options=("$@")
  option_count=${#options[@]}
  if [[ $option_count -eq 0 ]]; then
    return 1
  elif [[ $option_count -gt 2 || -n $done_option ]]; then
    for idx in "${!options[@]}"; do
      (( idx % 2 == 0 )) || continue
      printf "[%d] %s\n" $((idx / 2 + 1)) "${options[$(( idx + 1))]}" >&2
    done
    [[ -z $done_option ]] || printf "[0] %s\n" "$done_option" >&2
    local selected_option_idx
    while [[ -z $selected_option ]]; do
      printf '%s ' "$prompt" >&2
      read -r selected_option_idx
      if [[ -n $done_option ]] && [[ $selected_option_idx = 0 || $selected_option_idx = '' ]]; then
        printf ""
        break 2
      elif [[ $selected_option_idx =~ ^[0-9]+$ ]]; then
        for idx in "${!options[@]}"; do
          (( idx % 2 == 0 )) || continue
          if (( (selected_option_idx - 1) * 2 == idx )); then
            printf "%s"  "${options[$idx]}"
            break 2
          fi
        done
      fi
      printf "Invalid selection\n" >&2
    done
  else
    printf '%s ' "$prompt" >&2
    printf '"%s" (only 1 option)\n' "${options[1]}" >&2
    printf "%s\n" "${options[0]}"
  fi
}

get_control_plane_hostname() {
  jq -rse '[
    .[] | select((.["node-label"] // [])[] | contains("node-role.kubernetes.io/control-plane=true"))
  ] | first | .hostname' "$PKGROOT/startup/boot-server/registry/node-configs"/*.json
}
