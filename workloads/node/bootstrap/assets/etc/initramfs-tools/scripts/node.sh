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

download_node_config() {
  local boot_server primary_mac config_src_addr encrypted_response
  boot_server=$(get_node_state boot-server) || fatal "Unable to download node configuration: boot-server not present in node-state.json"
  primary_mac=$(get_node_state primary-mac) || fatal "Unable to download node configuration: primary-mac not present in node-state.json"
  config_src_addr=https://${boot_server}:8020/registry/node-config/${primary_mac//:/-}.json
  info "Downloading node-config from %s" "$config_src_addr"
  if encrypted_response=$(curl_boot_server "$config_src_addr"); then
    printf "%s\n" "$encrypted_response"
  else
    fatal "Downloading the node configuration failed"
  fi
}

decrypt_node_config() {
  local \
    node_key_path=$1 node_config_response=$2 \
    cipher encrypted_config calculated_hmac node_config

  cipher=$(
    jq -r '.["encrypted-chipher"]' <<<"$node_config_response" | \
    base64 -d | \
    openssl pkeyutl -pkeyopt rsa_padding_mode:oaep -inkey "$node_key_path" -decrypt | \
    base64 -w0
  )

  encrypted_config=$(jq -r '.["encrypted-config"]' <<<"$node_config_response")
  calculated_hmac=$(
    base64 -d <<<"$encrypted_config" | \
    openssl dgst -sha256 -binary -mac hmac -macopt hexkey:"$(base64 -d  <<<"$cipher" | tail -c +49 | xxd -p -c0)" | \
    base64 -w0
  )
  [[ $calculated_hmac = "$(jq -r '.["encrypted-config-hmac"]' <<<"$node_config_response")" ]] || \
    fatal "Calculated hmac does not match the hmac sent by the server"

  node_config=$(
    base64 -d <<<"$encrypted_config" |  openssl enc -d -aes-256-cbc \
      -iv "$(base64 -d  <<<"$cipher" | tail -c +33 | head -c 16 | xxd -p -c128)" \
      -K "$(base64 -d  <<<"$cipher" | head -c 32 | xxd -p -c128)"
  )
  set +x
  printf "%s" "$node_config"
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
