#!/usr/bin/env bash

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
