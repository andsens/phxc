#!/usr/bin/env bash

NODE_STATE=/run/initramfs/node-state.json

set_node_state() {
  local key=$1 val=$2 val_is_json=${3:-false} val_arg=--argjson
  $val_is_json || val_arg=--arg
  LOGPROGRAM=node-state.json verbose 'Setting "%s" to "%s"' "$key" "$val"
  # shellcheck disable=SC2016,SC2097,SC2098
  NODE_STATE=$NODE_STATE key=$key val=$val val_arg=$val_arg flock -x "$NODE_STATE" bash <<'EOR'
new_node_state=$(jq -re --arg key "$key" $val_arg val "$val" '.[$key]=$val' "$NODE_STATE")
printf "%s\n" "$new_node_state" > "$NODE_STATE"
EOR
}

get_node_state() {
  local key=$1
  # shellcheck disable=SC2016
  flock -s "$NODE_STATE" jq -re --arg key "$key" '.[$key]' "$NODE_STATE"
}
