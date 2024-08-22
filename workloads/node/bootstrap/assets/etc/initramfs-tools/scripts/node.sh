#!/usr/bin/env bash

NODE_STATE_PATH=/run/initramfs/node-state.json
NODE_CONFIG_PATH=/run/initramfs/node-config.json
NODE_KEY_PATH=/run/initramfs/node-key

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
    fatal "%s is not set in node-state.json" "$key"
  fi
}

report_node_state() {
  if boot_server_available; then
    local boot_server primary_mac node_state_sig node_state result
    boot_server=$(get_node_state boot-server) || return 1
    primary_mac=$(get_node_state primary-mac) || return 1
    node_state_sig=$(jq -c --sort-keys . $NODE_STATE_PATH | tr -d '\n' | openssl dgst -sha256 -sign $NODE_KEY_PATH | base64 -w0) || return 1
    node_state=$(jq --arg sig "$node_state_sig" '.signature=$sig' $NODE_STATE_PATH) || return 1
    if ! result=$(curl_boot_server -XPUT -d@<(printf "%s" "$node_state") -w '%{http_code}' \
      "https://${boot_server}:8020/registry/node-states/${primary_mac//:/-}.json" | tail -n1); then
      if [[ $result = 403 ]]; then
        fatal "Reporting node state not possible, node key is invalid"
      else
        warning "Failed to report node state"
      fi
    fi
  fi
}

get_node_config() {
  local key=$1
  if jq -r 'paths | join(".")' "$NODE_CONFIG_PATH" | grep -q "^$key$"; then
    key=$(escape_key "$key")
    jq -r ".$key" "$NODE_CONFIG_PATH"
  else
    fatal "%s is not set in node-config.json" "$key"
  fi
}

download_node_config() {
  local boot_server primary_mac encrypted_node_config
  boot_server=$(get_node_state boot-server) || return 1
  primary_mac=$(get_node_state primary-mac) || return 1
  curl_boot_server "https://${boot_server}:8020/registry/node-configs/${primary_mac//:/-}.json"
}

decrypt_node_config() {
  local encrypted_node_config=$1 \
    cipher encrypted_config calculated_hmac node_config

  cipher=$(
    jq -re '.["encrypted-chipher"]' <<<"$encrypted_node_config" | \
    base64 -d | \
    openssl pkeyutl -pkeyopt rsa_padding_mode:oaep -inkey "$NODE_KEY_PATH" -decrypt | \
    base64 -w0
  )

  encrypted_config=$(jq -re '.["encrypted-config"]' <<<"$encrypted_node_config")
  calculated_hmac=$(
    base64 -d <<<"$encrypted_config" | \
    openssl dgst -sha256 -binary -mac hmac -macopt hexkey:"$(base64 -d  <<<"$cipher" | tail -c +49 | xxd -p -c0)" | \
    base64 -w0
  )
  [[ $calculated_hmac = "$(jq -r '.["encrypted-config-hmac"]' <<<"$encrypted_node_config")" ]] || \
    fatal "Calculated hmac does not match the hmac sent by the server"

  node_config=$(
    base64 -d <<<"$encrypted_config" |  openssl enc -d -aes-256-cbc \
      -iv "$(base64 -d  <<<"$cipher" | tail -c +33 | head -c 16 | xxd -p -c128)" \
      -K "$(base64 -d  <<<"$cipher" | head -c 32 | xxd -p -c128)"
  )
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
