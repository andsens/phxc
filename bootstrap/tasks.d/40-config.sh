#!/usr/bin/env bash

config() {
  chmod 0755 /usr/local/bin/get-config
  mkdir /etc/phxc
  ln -sf ../run/machine-id /etc/machine-id
  ln -sf ../../../run/machine-id /var/lib/dbus/machine-id
  # Clear machine-id, let systemd generate one on first boot
  rm /var/lib/dbus/machine-id /etc/machine-id
  [[ ! -e /workspace/cluster.json ]] || cp /workspace/cluster.json /etc/phxc/cluster.json
  upkg add -g /usr/local/lib/upkg/.upkg/phxc/lib/common-context/jsonschema-cli.upkg.json
}
