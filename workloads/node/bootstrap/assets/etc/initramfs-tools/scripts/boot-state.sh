#!/usr/bin/env bash

BOOT_STATE=/run/initramfs/boot-state.json

set_boot_state() {
  local key=$1 val=$2
  LOGPROGRAM=boot-state.json verbose 'Setting "%s" to "%s"' "$key" "$val"
  if type flock &>/dev/null; then
    # shellcheck disable=SC2016,SC2097,SC2098
    BOOT_STATE=$BOOT_STATE key=$key val=$val flock -x "$BOOT_STATE" bash <<'EOR'
new_boot_state=$(jq -re --arg key "$key" --arg val "$val" '.[$key]=$val' "$BOOT_STATE")
printf "%s\n" "$new_boot_state" > "$BOOT_STATE"
EOR
  else
    local new_boot_state
    new_boot_state=$(jq -re --arg key "$key" --arg val "$val" '.[$key]=$val' "$BOOT_STATE")
    printf "%s\n" "$new_boot_state" > "$BOOT_STATE"
  fi
}

get_boot_state() {
  local key=$1
  if type flock &>/dev/null; then
    # shellcheck disable=SC2016
    flock -s "$BOOT_STATE" jq -re --arg key "$key" '.[$key]' "$BOOT_STATE"
  else
    jq -re --arg key "$key" '.[$key]' "$BOOT_STATE"
  fi
}
