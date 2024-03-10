#!/usr/bin/env bash

generate_replacement() {
  local name=$1 var
  shift
  printf 'apiVersion: v1
kind: ConfigMap
metadata:
  name: %s
  annotations:
    config.kubernetes.io/local-config: "true"
data:
' "$name"
  for var in "$@"; do
    printf "  %s: %s\n" "$var" "${!var}"
  done
}
