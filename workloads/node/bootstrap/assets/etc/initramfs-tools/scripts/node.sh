#!/usr/bin/env bash

NODE_STATE_PATH=/run/initramfs/node-state.json
NODE_CONFIG_PATH=/run/initramfs/node-config.json

set_node_state() {
  local key=$1 val=$2 val_is_json=${3:-false} val_arg=--argjson
  key=$(escape_key "$key")
  $val_is_json || val_arg=--arg
  LOGPROGRAM=node-state.json verbose 'Setting "%s" to "%s"' "$key" "$val"
  # shellcheck disable=SC2016,SC2097,SC2098
  NODE_STATE_PATH=$NODE_STATE_PATH key=$key val=$val val_arg=$val_arg flock -x "$NODE_STATE_PATH" bash <<'EOR'
new_node_state=$(jq -re $val_arg val "$val" ".$key=\$val" "$NODE_STATE_PATH")
printf "%s\n" "$new_node_state" > "$NODE_STATE_PATH"
EOR
}

get_node_state() {
  local key=$1
  if jq -r 'paths | join(".")' "$NODE_STATE_PATH" | grep -q "^$key$"; then
    key=$(escape_key "$key")
    # shellcheck disable=SC2016
    flock -s "$NODE_STATE_PATH" jq -r ".$key" "$NODE_STATE_PATH"
  else
    return 1
  fi
}

get_node_config() {
  local key=$1
  if jq -r 'paths | join(".")' "$NODE_CONFIG_PATH" | grep -q "^$key$"; then
    key=$(escape_key "$key")
    jq -r ".$key" "$NODE_CONFIG_PATH"
  else
    return 1
  fi
}

escape_key() {
  # Converts any path like some-path.to-something.here
  # into ["some-path"]["to-something"]["here"]
  # This means dots in keys are not allowed
  local key=$1
  key=${key//'.'/'"]["'}
  key="[\"$key\"]"
  printf "%s\n" "$key"
}
