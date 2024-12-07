#!/usr/bin/env bash

PACKAGES+=(
  yq # For converting node.yaml & cluster.yaml to json
  python3-jsonschema # For validating node.yaml & cluster.yaml
)

config() {
  cp_tpl -r /usr/local/lib/phxc/schemas
  cp_tpl --chmod 0755 /usr/local/bin/get-config
  mkdir /etc/phxc
  install_sd_unit config/copy-cluster-config.service
  install_sd_unit config/persist-machine-id.service
  install_sd_unit config/setup-admin-credentials.service
}
