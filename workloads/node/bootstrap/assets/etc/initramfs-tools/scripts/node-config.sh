#!/usr/bin/env bash

NODE_CONFIG=/run/initramfs/node-config.json

get_node_config() {
  local key=$1
  # shellcheck disable=SC2016
  jq -re ".$key" "$NODE_CONFIG"
}
