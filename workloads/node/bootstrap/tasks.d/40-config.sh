#!/usr/bin/env bash

PACKAGES+=(
  yq # For converting node.yaml & cluster.yaml to json
  python3-jsonschema # For validating node.yaml & cluster.yaml
)

config() {
  install_sd_unit 00-validate-boot-config.service
}
