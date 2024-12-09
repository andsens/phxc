#!/usr/bin/env bash

PACKAGES+=(
  yq # For converting config files to json
  python3-jsonschema # For validating config files
)

config() {
  mkdir /etc/phxc
  ln -sf ../run/machine-id /etc/machine-id
  ln -sf ../../../run/machine-id /var/lib/dbus/machine-id
  # Clear machine-id, let systemd generate one on first boot
  rm /var/lib/dbus/machine-id /etc/machine-id
  [[ ! -e /workspace/embed-configs ]] || cp /workspace/embed-configs/cluster.yaml /etc/phxc/cluster.yaml
}
