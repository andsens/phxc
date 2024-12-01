#!/usr/bin/env bash

PACKAGES+=(
  yq # For converting node.yaml & cluster.yaml to json
  python3-jsonschema # For validating node.yaml & cluster.yaml
)

config() {
  install_sd_unit config/copy-cluster-config.service
  install_sd_unit config/persist-machine-id.service
  install_sd_unit config/setup-admin-credentials.service
}
