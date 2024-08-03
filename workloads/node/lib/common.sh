#!/usr/bin/env bash

BOOT_STATE=/run/initramfs/boot-state.json
# shellcheck source=../../../.upkg/records.sh/records.sh
source "$PKGROOT/.upkg/records.sh/records.sh"

set_bootstate() {
  local key=$1 val=$2
  LOGPROGRAM=boot-state.json verbose 'Setting "%s" to "%s"' "$key" "$val"
  # shellcheck disable=SC2016
  flock -x "$BOOT_STATE" bash -c <<<EOR
new_boot_state=$(jq -re --arg key "$key" --arg val "$val" '.[$key]=$val' "$BOOT_STATE")
printf "%s\n" "$new_boot_state" > "$BOOT_STATE"
EOR
}

get_bootstate() {
  local key=$1
  # shellcheck disable=SC2016
  flock -s "$BOOT_STATE" jq -re --arg key "$key" '.[$key]' "$BOOT_STATE"
}
